#!/usr/bin/env python3
"""Preserve registered research assets locally and verify restoration.

No cloud upload, Git addition of corpora, removal, or source overwrite.
The destination must be outside this repository and remains on this host.
"""
import argparse
import datetime
import hashlib
import json
import os
import shutil
import tempfile
import uuid
from pathlib import Path


BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]


def digest(path):
    checksum = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            checksum.update(chunk)
    return checksum.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--report', type=Path, required=True)
    args = parser.parse_args()
    destination = args.destination.expanduser().resolve()
    if destination == REPO or REPO in destination.parents:
        raise ValueError('Snapshot destination must be outside the repository')
    registered = {}

    def register(filename, expected_hash=None):
        path = (REPO / filename).resolve()
        relative = path.relative_to(REPO)
        if not path.is_file():
            raise ValueError(f'Missing source {relative}')
        actual = digest(path)
        if expected_hash and actual != expected_hash:
            raise ValueError(f'Original digest mismatch: {relative}')
        existing = registered.get(str(relative))
        if existing and existing['sha256'] != actual:
            raise ValueError(f'Conflicting source versions: {relative}')
        registered[str(relative)] = {'path': str(relative),
                                     'bytes': path.stat().st_size, 'sha256': actual}

    acquisitions = json.loads((BASE / 'Registry/acquisitions.json').read_text())
    for row in acquisitions['acquisitions']:
        if row.get('path'):
            register(row['path'], row['sha256'])
        if row.get('manifest'):
            register(row['manifest'])
    processing = json.loads((BASE / 'Registry/processing.json').read_text())
    for run in processing['runs']:
        for page in run.get('page_records', []):
            if page.get('exit_code') != 0:
                continue
            output = page.get('output') or page['output_prefix'] + '.txt'
            register(output, page['sha256'])
            if page.get('tsv_output'):
                register(page['tsv_output'], page['tsv_sha256'])
    for path in BASE.rglob('*'):
        if path.is_file() and path.suffix in ('.json', '.md', '.py'):
            register(path.relative_to(REPO))

    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    snapshot_id = timestamp.replace(':', '').replace('+00:00', 'Z') + '-' + uuid.uuid4().hex[:8]
    snapshot = destination / snapshot_id
    snapshot.mkdir(mode=0o700)
    records = list(registered.values())
    for row in records:
        target = snapshot / row['path']
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        shutil.copyfile(REPO / row['path'], target)
        os.chmod(target, 0o600)
        if target.stat().st_size != row['bytes'] or digest(target) != row['sha256']:
            raise ValueError(f'Snapshot copy mismatch: {row["path"]}')

    restore_evidence = []
    with tempfile.TemporaryDirectory(prefix='restore-audit-', dir=destination) as scratch:
        for extension in ('.pdf', '.jpg', '.mp3', '.xlsx', '.txt', '.tsv'):
            candidate = next((r for r in records if r['path'].endswith(extension)), None)
            if not candidate:
                raise ValueError(f'No representative asset for {extension}')
            restored = Path(scratch) / ('restored' + extension)
            shutil.copyfile(snapshot / candidate['path'], restored)
            actual = digest(restored)
            if actual != candidate['sha256']:
                raise ValueError(f'Restore mismatch: {extension}')
            restore_evidence.append({'source': candidate['path'], 'extension': extension,
                                     'sha256': actual, 'restored_bytes': restored.stat().st_size})

    manifest = {'snapshot_id': snapshot_id, 'created_at_utc': timestamp,
                'snapshot_path': str(snapshot), 'files': records,
                'restore_evidence': restore_evidence,
                'limitations': ['Same-host local storage; no disk-loss/off-host restore test',
                                'New acquisitions require a new verified snapshot',
                                'Existing material rights and transmission limits still apply']}
    manifest_path = snapshot / 'snapshot-manifest.json'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
    os.chmod(manifest_path, 0o600)
    report = {'snapshot_id': snapshot_id, 'created_at_utc': timestamp,
              'snapshot_path': str(snapshot), 'manifest_path': str(manifest_path),
              'manifest_sha256': digest(manifest_path), 'files_verified': len(records),
              'bytes_verified': sum(r['bytes'] for r in records),
              'restore_evidence': restore_evidence, 'limitations': manifest['limitations']}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ('snapshot_id', 'files_verified', 'bytes_verified')}))


if __name__ == '__main__':
    main()
