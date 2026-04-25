#!/usr/bin/env python3
"""Shared helpers for local DaVinci Resolve development scripts."""

from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

RESOLVE_SCRIPTS_REL = r"Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility"


def detect_environment() -> str:
    if sys.platform == "win32":
        return "windows"

    if os.environ.get("WSL_DISTRO_NAME"):
        return "wsl"

    try:
        proc = Path("/proc/version").read_text(encoding="utf-8", errors="ignore").lower()
        if "microsoft" in proc or "wsl" in proc:
            return "wsl"
    except OSError:
        pass

    print(
        "ERROR: Unsupported environment. Run this script from Windows or WSL.",
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

    return run_command(
        ["powershell.exe", "-NoProfile", "-Command", "$env:APPDATA"],
        label="Resolving %APPDATA% via PowerShell",
    )


def to_wsl_path(win_path: str) -> Path:
    return Path(run_command(["wslpath", "-u", win_path], label=f"wslpath -u {win_path!r}"))


def resolve_default_destination(env: str, appdata_win: str, verbose: bool = False) -> Path:
    dest_win = os.path.join(appdata_win, RESOLVE_SCRIPTS_REL)
    if verbose:
        print(f"  Default destination (Windows path): {dest_win}")
    if env == "wsl":
        return to_wsl_path(dest_win)
    return Path(dest_win)


def validate_destination(dest: Path, appdata_win: str, env: str) -> None:
    if env == "wsl":
        appdata_root = to_wsl_path(appdata_win)
    else:
        appdata_root = Path(appdata_win)

    dest_lower = str(dest.resolve()).lower().replace("\\", "/")
    root_lower = str(appdata_root.resolve()).lower().replace("\\", "/")

    if not dest_lower.startswith(root_lower):
        print(
            f"ERROR: Destination '{dest}' is outside the per-user AppData tree.\n"
            f"  Expected a path under: {appdata_root}\n"
            f"  ProgramData and system-wide paths are not allowed.",
            file=sys.stderr,
        )
        sys.exit(1)


def resolve_temp_path(env: str, filename: str) -> Path:
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