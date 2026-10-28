#!/usr/bin/env python3
"""Publish up to three SHA-reviewed expansion batches within one maintenance budget."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def commands(plan):
    if not isinstance(plan, dict) or set(plan) != {'run', 'batches'} or plan['run'] not in {'2026-10-24', '2026-10-28'}:
        raise ValueError('An explicit supported run is required')
    rows = plan['batches']
    if not isinstance(rows, list) or not 1 <= len(rows) <= 3:
        raise ValueError('One to three bounded batches required')
    seen, result = set(), []
    for row in rows:
        if not isinstance(row, dict) or set(row) != {'batch', 'hash'} or not isinstance(row['batch'], str) or not isinstance(row['hash'], str) or not re.fullmatch(r'b[0-9]{3}', row['batch']) or not re.fullmatch(r'[a-f0-9]{64}', row['hash']) or row['batch'] in seen:
            raise ValueError('Invalid or duplicate reviewed publication identity')
        seen.add(row['batch'])
        result.append(['/opt/lingotrip/runtime/bin/node', '--expose-gc', '--max-old-space-size=128', '--env-file=/etc/lingotrip/backend.env', '--env-file=/etc/lingotrip/release.env', 'dist/cli/learning-expansion.js', 'publish', row['batch'], row['hash'], '--run', plan['run']])
    return result


if __name__ == '__main__':
    if os.geteuid() != 0 or '0::/system.slice/lingotrip-maintenance.service' not in Path('/proc/self/cgroup').read_text().splitlines():
        raise SystemExit('Maintenance scope required')
    for command in commands(json.loads(Path(sys.argv[1]).read_text())):
        subprocess.run(command, check=True)
