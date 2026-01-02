from __future__ import annotations

import argparse
import json
import sys

from canvassheets_api import FormulaLocals, Project, export_numpy_script


def run_script(path: str) -> Project:
    globals_dict = FormulaLocals({"__file__": path, "__name__": "__main__", "__builtins__": __builtins__})
    with open(path, "r", encoding="utf-8") as handle:
        source = handle.read()
    exec(compile(source, path, "exec"), globals_dict, globals_dict)
    proj = globals_dict.get("proj")
    if not isinstance(proj, Project):
        raise RuntimeError("Script must define `proj = Project()`")
    proj.apply_formulas()
    return proj


def main() -> int:
    parser = argparse.ArgumentParser(description="Run a CanvasSheets script and emit project JSON.")
    parser.add_argument("script", help="Path to the Python script to run.")
    parser.add_argument("--export-numpy", action="store_true",
                        help="Emit a standalone NumPy script instead of project JSON.")
    parser.add_argument("--include-formulas", action="store_true",
                        help="Include formula definitions in exported NumPy script.")
    args = parser.parse_args()

    try:
        project = run_script(args.script)
    except Exception as exc:  # pylint: disable=broad-except
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    if args.export_numpy:
        export_script = export_numpy_script(project, include_labels=True, include_formulas=args.include_formulas)
        print(export_script)
        return 0

    payload = project.to_dict()
    print(json.dumps(payload, sort_keys=True, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
