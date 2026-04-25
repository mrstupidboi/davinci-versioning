#!/usr/bin/env python3
r"""
Deploy a DaVinci Resolve Python script to the per-user Resolve Scripts folder.

Works from both WSL and native Windows. Destination is always the per-user
AppData Resolve Scripts/Utility folder.

Usage:
    python tools/deploy.py [SOURCE] [--destination PATH] [--dry-run] [--verbose]
"""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from shared.resolve_tooling import (
    detect_environment,
    get_appdata_win,
    resolve_default_destination,
    to_wsl_path,
    validate_destination,
)


def copy_script(source: Path, dest_dir: Path, dry_run: bool, verbose: bool) -> None:
    dest_file = dest_dir / source.name

    if dry_run:
        print(f"[dry-run] Source      : {source}")
        print(f"[dry-run] Destination : {dest_file}")
        print("[dry-run] No files were changed.")
        return

    if not dest_dir.exists():
        print(
            f"ERROR: Destination folder does not exist: {dest_dir}\n"
            "  Open DaVinci Resolve once to create its script directories, then retry.",
            file=sys.stderr,
        )
        sys.exit(1)

    shutil.copy2(source, dest_file)
    if verbose:
        print("  Copied via shutil.copy2")

    print(f"Deployed: {source.name} -> {dest_file}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Deploy a DaVinci Resolve script to the per-user Resolve Scripts folder.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    default_source = Path(__file__).resolve().parent.parent / "davinci-versioning.py"
    parser.add_argument(
        "source",
        metavar="SOURCE",
        nargs="?",
        default=str(default_source),
        help="Path to the .py script to deploy. Defaults to davinci-versioning.py in the repo root.",
    )
    parser.add_argument(
        "--destination",
        metavar="PATH",
        help="Override deployment destination folder. Must be inside the per-user AppData Resolve scripts tree.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print resolved paths without copying.")
    parser.add_argument("--verbose", action="store_true", help="Print extra diagnostics during deployment.")
    args = parser.parse_args()

    env = detect_environment()
    if args.verbose:
        print(f"Environment : {env}")

    source = Path(args.source).resolve()
    if not source.is_file():
        print(f"ERROR: Source file not found: {source}", file=sys.stderr)
        sys.exit(1)
    if args.verbose:
        print(f"Source      : {source}")

    appdata_win = get_appdata_win(env)
    if args.destination:
        raw = args.destination
        if env == "wsl" and not raw.startswith("/"):
            dest = to_wsl_path(raw)
        else:
            dest = Path(raw)
        validate_destination(dest, appdata_win, env)
    else:
        dest = resolve_default_destination(env, appdata_win, args.verbose)

    if args.verbose or args.dry_run:
        print(f"Destination : {dest}")

    copy_script(source, dest, args.dry_run, args.verbose)


if __name__ == "__main__":
    main()