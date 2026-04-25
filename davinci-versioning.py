r"""
DaVinci Resolve Auto-Version Render Job for Windows (Python)

Checks the output folder for existing files and creates the next _v## filename.

Install to:
    C:\ProgramData\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Utility
"""

from __future__ import annotations

import os
import re
import sys
import tempfile
from pathlib import Path
from tkinter import Tk, filedialog

dvr_script = None


# ------------------------------------------------------------
# USER SETTINGS
# ------------------------------------------------------------

# Optional fallback if the current project has no render jobs to infer a folder from.
# Leave as None to require an existing render job in the project.
FALLBACK_OUTPUT_FOLDER = None

# Version format: _v01, _v02, etc.
VERSION_DIGITS = 2

# ------------------------------------------------------------
# HELPERS
# ------------------------------------------------------------

def log_line(lines: list[str], text: object) -> None:
    message = str(text)
    lines.append(message)
    print(message)


def write_log(lines: list[str]) -> None:
    log_path = Path(tempfile.gettempdir()) / "resolve_auto_version_render_log.txt"
    log_path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def prompt_for_output_folder(lines: list[str]) -> Path | None:
    root = Tk()
    root.withdraw()
    root.attributes("-topmost", True)

    try:
        selected = filedialog.askdirectory(
            title="Choose Resolve Export Folder",
            mustexist=True,
        )
    finally:
        root.destroy()

    if not selected:
        log_line(lines, "ERROR: No output folder was selected.")
        return None

    selected_path = Path(selected)
    log_line(lines, f"Selected output folder from prompt: {selected_path}")
    return selected_path


def sanitize_filename(name: object) -> str:
    sanitized = re.sub(r'[<>:"/\\|?*]', "_", str(name or "Untitled")).strip()
    return sanitized or "Untitled"


def get_existing_versions(
    folder: Path, base_name: str, extension: str, lines: list[str]
) -> list[int]:
    versions: list[int] = []
    pattern = re.compile(
        rf"^{re.escape(base_name)}_v(\d+)\.{re.escape(extension)}$",
        re.IGNORECASE,
    )

    log_line(lines, f"Scanning folder: {folder}")

    for path in folder.glob(f"{base_name}_v*.{extension}"):
        log_line(lines, f"Found matching-ish file: {path.name}")
        match = pattern.match(path.name)
        if match:
            version = int(match.group(1))
            versions.append(version)
            log_line(lines, f"Parsed version: {version}")
        else:
            log_line(
                lines,
                "Skipped file because it did not match expected pattern exactly.",
            )

    return versions


def next_version_number(folder: Path, base_name: str, extension: str, lines: list[str]) -> int:
    versions = get_existing_versions(folder, base_name, extension, lines)
    return (max(versions) if versions else 0) + 1


def get_resolve():
    if dvr_script is None:
        return None

    try:
        return dvr_script.scriptapp("Resolve")
    except Exception:
        return None


def load_resolve_script_module(lines: list[str]):
    global dvr_script

    if dvr_script is not None:
        return dvr_script

    try:
        import DaVinciResolveScript as imported_module

        dvr_script = imported_module
        log_line(lines, "Loaded DaVinciResolveScript from Python import path.")
        return dvr_script
    except ImportError:
        pass

    candidate_module_dirs = [
        Path(os.environ.get("RESOLVE_SCRIPT_API", "")) / "Modules",
        Path(r"C:\ProgramData\Blackmagic Design\DaVinci Resolve\Support\Developer\Scripting\Modules"),
        Path(r"C:\Program Files\Blackmagic Design\DaVinci Resolve\Developer\Scripting\Modules"),
    ]

    for module_dir in candidate_module_dirs:
        if not str(module_dir):
            continue
        candidate = module_dir / "DaVinciResolveScript.py"
        if candidate.is_file():
            module_dir_str = str(module_dir)
            inserted = False
            if module_dir_str not in sys.path:
                sys.path.insert(0, module_dir_str)
                inserted = True
            try:
                import DaVinciResolveScript as imported_module

                dvr_script = imported_module
                log_line(lines, f"Loaded DaVinciResolveScript from: {candidate}")
                return dvr_script
            except ImportError as exc:
                log_line(lines, f"Import failed from {candidate}: {exc}")
            finally:
                if inserted:
                    try:
                        sys.path.remove(module_dir_str)
                    except ValueError:
                        pass

    log_line(lines, "Could not find DaVinciResolveScript.py in standard Resolve locations.")
    return None


def get_current_extension(project, lines: list[str]) -> str | None:
    current_render = project.GetCurrentRenderFormatAndCodec()
    if not current_render:
        log_line(lines, "ERROR: Could not read current render format/codec from Resolve.")
        return None

    render_format = current_render.get("format")
    render_codec = current_render.get("codec")
    log_line(lines, f"Current render format: {render_format}")
    log_line(lines, f"Current render codec: {render_codec}")

    if not render_format:
        log_line(lines, "ERROR: Resolve did not return a current render format.")
        return None

    render_formats = project.GetRenderFormats()
    if not render_formats:
        log_line(lines, "ERROR: Could not read available render formats from Resolve.")
        return None

    log_line(lines, f"Available render formats: {render_formats}")

    extension = None

    # Resolve returns the current format as an internal code like "mp4" or "mov",
    # while GetRenderFormats() uses display names like "MP4" or "QuickTime" as keys
    # and the file extension as the value.
    if render_format in render_formats.values():
        extension = render_format
    else:
        for format_name, format_extension in render_formats.items():
            if format_name.lower() == render_format.lower():
                extension = format_extension
                break
            if format_extension.lower() == render_format.lower():
                extension = format_extension
                break

    if not extension:
        log_line(
            lines,
            f"ERROR: Could not map render format '{render_format}' to a file extension.",
        )
        return None

    log_line(lines, f"Resolved file extension: {extension}")
    return extension


def get_project_output_folder(project, lines: list[str]) -> tuple[Path, bool] | None:
    render_jobs = project.GetRenderJobList()
    if render_jobs:
        latest_job = render_jobs[-1]
        target_dir = latest_job.get("TargetDir")
        output_filename = latest_job.get("OutputFilename")
        log_line(lines, f"Using output folder from latest render job: {target_dir}")
        log_line(lines, f"Latest render job filename: {output_filename}")
        if target_dir:
            output_folder = Path(target_dir)
            if output_folder.is_dir():
                return output_folder, False
            log_line(lines, f"ERROR: Latest render job folder does not exist: {output_folder}")
            return None

    if FALLBACK_OUTPUT_FOLDER:
        output_folder = Path(FALLBACK_OUTPUT_FOLDER)
        log_line(lines, f"Using fallback output folder: {output_folder}")
        if output_folder.is_dir():
            return output_folder, True
        log_line(lines, f"ERROR: Fallback output folder does not exist: {output_folder}")
        return None

    log_line(lines, "No render jobs found for this project. Prompting for output folder.")
    prompted_folder = prompt_for_output_folder(lines)
    if not prompted_folder:
        return None
    return prompted_folder, True


# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------

def main() -> None:
    lines: list[str] = []
    log_line(lines, "Resolve Auto-Version Render (Python)")
    log_line(lines, "------------------------------------")

    load_resolve_script_module(lines)
    resolve = get_resolve()
    if not resolve:
        log_line(lines, "ERROR: Could not connect to Resolve.")
        if dvr_script is None:
            log_line(
                lines,
                "DaVinciResolveScript could not be imported. Run this from Resolve or configure the Resolve Python API environment.",
            )
        write_log(lines)
        return

    project_manager = resolve.GetProjectManager()
    if not project_manager:
        log_line(lines, "ERROR: Could not get Project Manager.")
        write_log(lines)
        return

    project = project_manager.GetCurrentProject()
    if not project:
        log_line(lines, "ERROR: No project is open.")
        write_log(lines)
        return

    output_folder_info = get_project_output_folder(project, lines)
    if not output_folder_info:
        write_log(lines)
        return
    output_folder, should_set_target_dir = output_folder_info

    log_line(lines, f"Resolved output folder: {output_folder}")

    extension = get_current_extension(project, lines)
    if not extension:
        write_log(lines)
        return

    timeline = project.GetCurrentTimeline()
    if not timeline:
        log_line(lines, "ERROR: No timeline is open.")
        write_log(lines)
        return

    base_name = sanitize_filename(timeline.GetName())
    log_line(lines, f"Timeline/base name: {base_name}")

    next_v = next_version_number(output_folder, base_name, extension, lines)
    custom_name = f"{base_name}_v{next_v:0{VERSION_DIGITS}d}"
    log_line(lines, f"Next filename without extension: {custom_name}")
    log_line(lines, f"Expected full file: {output_folder}\\{custom_name}.{extension}")

    # Preserve the Deliver page format settings, and only set TargetDir when we had
    # to infer it ourselves because the project had no usable render-job location yet.
    render_settings = {
        "CustomName": custom_name,
    }
    if should_set_target_dir:
        render_settings["TargetDir"] = str(output_folder)
        log_line(lines, f"Applying TargetDir from fallback selection: {output_folder}")

    ok = project.SetRenderSettings(render_settings)

    if not ok:
        log_line(
            lines,
            "ERROR: SetRenderSettings failed. Open the Deliver page once, choose your render preset/settings, then try again.",
        )
        write_log(lines)
        return

    job_id = project.AddRenderJob()
    if not job_id:
        log_line(
            lines,
            "ERROR: AddRenderJob failed. Open the Deliver page and make sure render settings are valid.",
        )
        write_log(lines)
        return

    log_line(lines, f"SUCCESS: Added render job ID: {job_id}")
    log_line(lines, "Now check Deliver page > Render Queue.")
    write_log(lines)


if __name__ == "__main__":
    main()
