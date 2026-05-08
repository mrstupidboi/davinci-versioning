#!/usr/bin/env python3
"""Shared helpers for local DaVinci Resolve development scripts."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

RESOLVE_SCRIPTS_REL_WIN = r"Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility"
RESOLVE_SCRIPTS_REL_MAC = Path(
    "Blackmagic Design",
    "DaVinci Resolve",
    "Fusion",
    "Scripts",
    "Utility",
)


def detect_environment() -> str:
    if sys.platform == "win32":
        return "windows"

    if sys.platform == "darwin":
        return "macos"

    if os.environ.get("WSL_DISTRO_NAME"):
        return "wsl"

    try:
        proc = Path("/proc/version").read_text(encoding="utf-8", errors="ignore").lower()
        if "microsoft" in proc or "wsl" in proc:
            return "wsl"
    except OSError:
        pass

    print(
        "ERROR: Unsupported environment. Run this script from macOS, Windows, or WSL.",
        file=sys.stderr,
    )
    sys.exit(1)


def run_command(cmd: list[str], *, label: str) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not result.stdout.strip():
        print(f"ERROR: {label} failed.\n{result.stderr.strip()}", file=sys.stderr)
        sys.exit(1)
    return result.stdout.strip()


def get_appdata_win(env: str) -> str:
    if env == "windows":
        value = os.environ.get("APPDATA")
        if not value:
            print("ERROR: %APPDATA% environment variable is not set.", file=sys.stderr)
            sys.exit(1)
        return value

    if env == "macos":
        print("ERROR: %APPDATA% is only available on Windows/WSL.", file=sys.stderr)
        sys.exit(1)

    return run_command(
        ["powershell.exe", "-NoProfile", "-Command", "$env:APPDATA"],
        label="Resolving %APPDATA% via PowerShell",
    )


def get_user_support_root(env: str) -> Path | str:
    if env == "macos":
        return Path.home() / "Library" / "Application Support"

    return get_appdata_win(env)


def get_system_support_root(env: str) -> Path | None:
    if env == "macos":
        return Path("/Library/Application Support")

    return None


def to_wsl_path(win_path: str) -> Path:
    return Path(run_command(["wslpath", "-u", win_path], label=f"wslpath -u {win_path!r}"))


def resolve_default_destination(env: str, user_support_root: Path | str, verbose: bool = False) -> Path:
    if env == "macos":
        dest = Path(user_support_root) / RESOLVE_SCRIPTS_REL_MAC
        if verbose:
            print(f"  Default destination (macOS path): {dest}")
        return dest

    appdata_win = str(user_support_root)
    dest_win = os.path.join(appdata_win, RESOLVE_SCRIPTS_REL_WIN)
    if verbose:
        print(f"  Default destination (Windows path): {dest_win}")
    if env == "wsl":
        return to_wsl_path(dest_win)
    return Path(dest_win)


def validate_destination(dest: Path, user_support_root: Path | str, env: str) -> None:
    if env == "wsl":
        allowed_roots = [to_wsl_path(str(user_support_root))]
        expected_label = "per-user AppData tree"
    elif env == "macos":
        allowed_roots = [Path(user_support_root)]
        system_support_root = get_system_support_root(env)
        if system_support_root:
            allowed_roots.append(system_support_root)
        expected_label = "macOS Application Support tree"
    else:
        allowed_roots = [Path(user_support_root)]
        expected_label = "per-user AppData tree"

    dest_resolved = dest.resolve()
    is_under_root = False
    for allowed_root in allowed_roots:
        root_resolved = allowed_root.resolve()
        try:
            is_under_root = os.path.commonpath([dest_resolved, root_resolved]) == str(root_resolved)
        except ValueError:
            is_under_root = False
        if is_under_root:
            break

    if not is_under_root:
        expected_roots = "\n".join(f"  - {root}" for root in allowed_roots)
        print(
            f"ERROR: Destination '{dest}' is outside the {expected_label}.\n"
            f"  Expected a path under:\n{expected_roots}\n"
            f"  Other system paths are not allowed.",
            file=sys.stderr,
        )
        sys.exit(1)


def resolve_temp_path(env: str, filename: str) -> Path:
    if env == "macos":
        return Path(os.environ.get("TMPDIR", "/tmp")) / filename

    if env == "windows":
        temp = os.environ.get("TEMP") or os.environ.get("TMP")
        if not temp:
            print("ERROR: %TEMP% environment variable is not set.", file=sys.stderr)
            sys.exit(1)
        return Path(temp) / filename

    temp_win = run_command(
        ["powershell.exe", "-NoProfile", "-Command", "$env:TEMP"],
        label="Resolving %TEMP% via PowerShell",
    )
    return to_wsl_path(temp_win) / filename
