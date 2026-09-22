#!/usr/bin/env python3
"""Check synthetic device evidence, including incomplete batches. Makes no requests."""
import argparse
import json
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("report", type=Path)
    parser.add_argument("--expected-count", required=True, type=int)
    args = parser.parse_args()
    if args.expected_count <= 0:
        parser.error("--expected-count must be positive")
    rows = json.loads(args.report.read_text())
    problems = []
    if not isinstance(rows, list) or not all(isinstance(row, dict) for row in rows):
        raise SystemExit("Invalid report: expected an array of records")
    if len(rows) != args.expected_count:
        problems.append(f"incomplete/unexpected batch: {len(rows)}/{args.expected_count}")
    names = [row.get("case") for row in rows]
    if len(set(names)) != len(names) or any(not name for name in names):
        problems.append("duplicate or missing case names")
    for field in ("runID", "fixtureVersion"):
        values = {row.get(field) for row in rows}
        if len(values) > 1:
            problems.append(f"mixed runs or partial metadata: {field}")
    calls = 0
    for row in rows:
        name = row.get("case", "unknown")
        expected, actual = row.get("expectedComplete"), row.get("actualComplete")
        if expected not in ("true", "false") or actual not in ("true", "false"):
            problems.append(f"{name}: invalid expected/actual values")
        if expected != actual or row.get("matched") != "true" or row.get("error"):
            problems.append(f"{name}: mismatch or evaluation error")
        try:
            count = int(row.get("reviewCalls", ""))
        except (ValueError, TypeError):
            count = 0
        calls += count
        if count not in (1, 2):
            problems.append(f"{name}: missing/out-of-bounds call count")
        if not row.get("feedback", "").strip() or not row.get("response", "").strip():
            problems.append(f"{name}: missing feedback/raw response")
    print(f"{len(rows)} records, {calls} client calls, {len(problems)} issues")
    uncertain = [row["case"] for row in rows if row.get("assessmentVerdict") == "uncertain"]
    if uncertain:
        print("Uncertain (not a confident semantic judgement): " + ", ".join(uncertain))
    for problem in problems:
        print(problem)
    print("Semantic feedback and evidence still require human review.")
    raise SystemExit(bool(problems))


if __name__ == "__main__":
    main()
