"""Run a recorded script and emit the project as JSON.

The script is executed in a *normal* module namespace — there is no custom
``locals`` magic. The very same file runs under ``python script.py``. The runner
just locates the resulting ``proj`` (a :class:`Project`), calls ``proj.run()``,
and serializes it.
"""

from __future__ import annotations

import runpy
from typing import Optional

from .project import Project


def run_script(path: str) -> Project:
    namespace = runpy.run_path(path, run_name="__main__")
    proj = _find_project(namespace)
    if proj is None:
        raise RuntimeError(
            "Script did not define a Project. Expected a module-level `proj = Project()`."
        )
    proj.run()
    return proj


def _find_project(namespace: dict) -> Optional[Project]:
    candidate = namespace.get("proj")
    if isinstance(candidate, Project):
        return candidate
    # fall back to any Project in the namespace
    for value in namespace.values():
        if isinstance(value, Project):
            return value
    return None
