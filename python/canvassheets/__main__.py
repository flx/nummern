"""CLI entry point: ``python -m canvassheets run script.py --emit json``."""

from __future__ import annotations

import argparse
import sys
import traceback

from . import export as _export
from . import io as _io
from .runner import run_script


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="canvassheets")
    sub = parser.add_subparsers(dest="command", required=True)

    run = sub.add_parser("run", help="Run a script and emit its project state.")
    run.add_argument("script")
    run.add_argument("--emit", choices=["json", "numpy", "matplotlib"], default="json")
    run.add_argument("--include-formulas", action="store_true",
                     help="(numpy export) rebuild via canvassheets and recompute formulas.")

    args = parser.parse_args(argv)

    if args.command == "run":
        try:
            project = run_script(args.script)
        except Exception:
            traceback.print_exc()
            return 1
        if args.emit == "json":
            print(_io.to_json(project))
        elif args.emit == "numpy":
            print(_export.export_numpy_script(project, include_formulas=args.include_formulas))
        elif args.emit == "matplotlib":
            print(_export.export_matplotlib_script(project))
        return 0

    return 2


if __name__ == "__main__":
    sys.exit(main())
