"""Proves recorded scripts are real, standalone Python."""

import json
import subprocess
import sys
from pathlib import Path

FIXTURE = Path(__file__).parent / "fixtures" / "canonical.py"


def test_canonical_runs_as_plain_python():
    """`python canonical.py` works with no harness — the headline guarantee."""
    result = subprocess.run(
        [sys.executable, str(FIXTURE)],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    # F = row sums [52, 92, 132, 172]; grand total = 448
    assert "grand total: 448.0" in result.stdout


def test_runner_emits_json():
    from canvassheets.runner import run_script
    from canvassheets import to_dict

    proj = run_script(str(FIXTURE))
    data = to_dict(proj)
    table = next(t for s in data["sheets"] for t in s["tables"] if t["id"] == "table_1")
    # column F (index 5) holds the row totals
    totals = table["body"][5]
    assert totals == [52, 92, 132, 172]


def test_cli_run_emit_json():
    result = subprocess.run(
        [sys.executable, "-m", "canvassheets", "run", str(FIXTURE), "--emit", "json"],
        capture_output=True, text=True, check=False,
    )
    assert result.returncode == 0, result.stderr
    payload = json.loads(result.stdout.strip().splitlines()[-1])
    assert payload["version"] == 1
    assert any(t["id"] == "table_2" for s in payload["sheets"] for t in s["tables"])
