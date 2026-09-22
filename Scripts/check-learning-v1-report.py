#!/usr/bin/env python3
"""Validate real v1 evaluation output; transport errors never count as negative answers."""
import argparse
import json
import sys
from pathlib import Path


def problems(report, expected_count):
    issues = []
    rows = report.get('rows', [])
    if report.get('complete') is not True:
        issues.append('run did not finish')
    if not rows or len(rows) != expected_count:
        issues.append(f'expected {expected_count} rows, received {len(rows)}')
    ids = [r.get('id') for r in rows]
    if len(set(ids)) != len(ids) or any(not x for x in ids):
        issues.append('missing or repeated case IDs')
    for row in rows:
        name = row.get('id', '<missing>')
        if row.get('error') or type(row.get('actual')) is not bool:
            issues.append(f'{name}: no valid model judgment ({row.get("error", "missing result")})')
        elif type(row.get('expected')) is not bool or row['actual'] != row['expected']:
            issues.append(f'{name}: expected {row.get("expected")}, got {row["actual"]}; {row.get("explanations", [])}')
        if row.get('expectedSkills') is not None and not set(row['expectedSkills']).issubset(set(row.get('actualSkills') or [])):
            issues.append(f'{name}: missing expected skill: {row["expectedSkills"]}; actual {row.get("actualSkills")}')
        if row.get('expectedPaused') is not None and row.get('paused') != row['expectedPaused']:
            issues.append(f'{name}: incorrect pause behavior')
    return issues


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('report', type=Path)
    parser.add_argument('--expected-count', type=int, required=True)
    args = parser.parse_args()
    report = json.loads(args.report.read_text())
    issues = problems(report, args.expected_count)
    if issues:
        print('\n'.join(issues)); sys.exit(1)
    retries = sum(len(r.get('failedAttempts', [])) for r in report['rows'])
    print(f'Recorded failed attempts before recovery: {retries}; retained in report, not counted as first-attempt successes.')
    seconds = sum(r.get('seconds', 0) for r in report['rows'])
    print(f'{len(report["rows"])} real model cases passed; mean request time {seconds / len(report["rows"]):.2f}s. Not a population accuracy estimate.')
