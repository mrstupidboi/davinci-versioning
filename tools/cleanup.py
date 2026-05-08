#!/usr/bin/env python3
"""Remove a deployed DaVinci Resolve script from the per-user scripts folder."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.dont_write_bytecode = True

from shared.resolve_tooling import (
    detect_environment,
    get_user_support_root,
    resolve_default_destination,
    to_wsl_path,
    validate_destination,
)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Remove a deployed DaVinci Resolve script from the per-user Resolve Scripts folder.",
    )
    parser.add_argument(
        "name",
        metavar="SCRIPT_NAME",
        nargs="?",
        default="davinci-versioning.lua",
        help="Script filename to remove. Defaults to davinci-versioning.lua.",
    )
    parser.add_argument(
        "--destination",
        metavar="PATH",
        help="Override deployed script directory. Must be inside the per-user Resolve support tree.",
    )
    parser.add_argument("--dry-run", action="store_true", help="Print the resolved file path without deleting it.")
    parser.add_argument("--verbose", action="store_true", help="Print extra diagnostics during cleanup.")
    args = parser.parse_args()

    env = detect_environment()
    if args.verbose:
        print(f"Environment : {env}")

    user_support_root = get_user_support_root(env)
    if args.destination:
        raw = args.destination
        if env == "wsl" and not raw.startswith("/"):
            dest_dir = to_wsl_path(raw)
        else:
            dest_dir = Path(raw).expanduser()
        validate_destination(dest_dir, user_support_root, env)
    else:
        dest_dir = resolve_default_destination(env, user_support_root, args.verbose)

    target = dest_dir / args.name
    if args.verbose or args.dry_run:
        print(f"Target      : {target}")

    if args.dry_run:
        print("[dry-run] No files were changed.")
        return

    if not target.exists():
        print(f"ERROR: Deployed script not found: {target}", file=sys.stderr)
        sys.exit(1)

    target.unlink()
    print(f"Removed: {target}")


if __name__ == "__main__":
    main()
