#!/usr/bin/env python3
"""Print a DaVinci Resolve script log from the Windows temp directory."""

from __future__ import annotations

import argparse
import sys

sys.dont_write_bytecode = True

from shared.resolve_tooling import detect_environment, resolve_temp_path

DEFAULT_LOG_FILENAME = "resolve_auto_version_render_log.txt"


def main() -> None:
    parser = argparse.ArgumentParser(description="Print a Resolve script log file.")
    parser.add_argument("--path", action="store_true", help="Print the resolved log path without reading the file.")
    parser.add_argument(
        "--name",
        default=DEFAULT_LOG_FILENAME,
        help="Log filename inside the Windows TEMP directory.",
    )
    args = parser.parse_args()

    env = detect_environment()
    log_path = resolve_temp_path(env, args.name)

    if args.path:
        print(log_path)
        return

    if not log_path.exists():
        print(f"No log file found at: {log_path}", file=sys.stderr)
        print("Run the corresponding script from DaVinci Resolve first.", file=sys.stderr)
        sys.exit(1)

    print(log_path.read_text(encoding="utf-8", errors="replace"), end="")


if __name__ == "__main__":
    main()