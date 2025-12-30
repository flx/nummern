from __future__ import annotations

import argparse
import json
import sys

from canvassheets_api import Project


def run_script(path: str) -> Project:
    globals_dict = {"__file__": path, "__name__": "__main__"}
    with open(path, "r", encoding="utf-8") as handle:
        source = handle.read()
    exec(compile(source, path, "exec"), globals_dict, globals_dict)
    proj = globals_dict.get("proj")
    if not isinstance(proj, Project):
        raise RuntimeError("Script must define `proj = Project()`")
    return proj


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a CanvasSheets script and emit project JSON.")
    parser.add_argument("script", help="Path to the Python script to run.")
    args = parser.parse_args()

    try:
        project = run_script(args.script)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    payload = project.to_dict()
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
