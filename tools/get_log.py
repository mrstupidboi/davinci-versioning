#!/usr/bin/env python3
"""Print a DaVinci Resolve script log from the host temp directory."""

from __future__ import annotations

import argparse
import os
import sys
from datetime import datetime
from pathlib import Path

sys.dont_write_bytecode = True

from shared.resolve_tooling import (
    detect_environment,
    get_system_support_root,
    get_user_support_root,
    resolve_default_destination,
    resolve_temp_path,
)

DEFAULT_LOG_FILENAME = "resolve_auto_version_render_log.txt"
DEFAULT_SCRIPT_NAMES = (
    "davinci-versioning.lua",
    "davinci-versioning.py",
    "davinci-toggle-noise-reduction.lua",
    "davinci-toggle-noise-reduction_v_2.lua",
    "davinci-toggle-ai-ultra-sharpen_v_1.lua",
    "davinci-toggle-color-effects_v_1.lua",
)


def format_mtime(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp).strftime("%Y-%m-%d %H:%M:%S")


def describe_path(path: Path) -> str:
    if not path.exists():
        return f"{path} [missing]"

    stat = path.stat()
    kind = "dir" if path.is_dir() else "file"
    return f"{path} [{kind}, {stat.st_size} bytes, modified={format_mtime(stat.st_mtime)}]"


def script_dirs(env: str) -> list[Path]:
    dirs = [resolve_default_destination(env, get_user_support_root(env))]
    system_support_root = get_system_support_root(env)
    if system_support_root:
        dirs.append(resolve_default_destination(env, system_support_root))
    return dirs


def print_debug(env: str, log_path: Path, names: list[str]) -> None:
    newest_script_mtime = 0.0

    print(f"Environment : {env}")
    print(f"TMPDIR      : {os.environ.get('TMPDIR')}")
    print(f"TEMP        : {os.environ.get('TEMP')}")
    print(f"TMP         : {os.environ.get('TMP')}")
    print(f"Log path    : {describe_path(log_path)}")
    print()
    print("Script locations:")
    for directory in script_dirs(env):
        print(f"  {describe_path(directory)}")
        for name in names:
            script_path = directory / name
            print(f"    {describe_path(script_path)}")
            if script_path.exists() and script_path.stat().st_mtime > newest_script_mtime:
                newest_script_mtime = script_path.stat().st_mtime

    if log_path.exists() and newest_script_mtime and log_path.stat().st_mtime < newest_script_mtime:
        print()
        print(
            "Note        : Log is older than the newest deployed script. "
            "Run the script in Resolve again to refresh it."
        )


def main() -> None:
    parser = argparse.ArgumentParser(description="Print a Resolve script log file.")
    parser.add_argument("--path", action="store_true", help="Print the resolved log path without reading the file.")
    parser.add_argument("--debug", action="store_true", help="Print resolved paths and deployed script diagnostics.")
    parser.add_argument(
        "--name",
        default=DEFAULT_LOG_FILENAME,
        help="Log filename inside the host temp directory.",
    )
    parser.add_argument(
        "--script-name",
        action="append",
        dest="script_names",
        help="Script filename to include in --debug output. Can be passed more than once.",
    )
    args = parser.parse_args()

    env = detect_environment()
    log_path = resolve_temp_path(env, args.name)
    names = args.script_names or list(DEFAULT_SCRIPT_NAMES)

    if args.path:
        print(log_path)
        return

    if args.debug:
        print_debug(env, log_path, names)
        if not log_path.exists():
            return
        print()
        print("Log contents:")

    if not log_path.exists():
        print(f"No log file found at: {log_path}", file=sys.stderr)
        print("Run the corresponding script from DaVinci Resolve first.", file=sys.stderr)
        sys.exit(1)

    print(log_path.read_text(encoding="utf-8", errors="replace"), end="")


if __name__ == "__main__":
    main()
