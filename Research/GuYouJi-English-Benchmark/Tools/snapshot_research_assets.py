#!/usr/bin/env python3
"""Preserve registered research assets locally and verify restoration.

No cloud upload, Git addition of corpora, removal, or source overwrite.
The destination must be outside this repository and remains on this host.
"""
import argparse
import collections
import ctypes
import datetime
import hashlib
import json
import os
import shutil
import sys
import tempfile
import uuid
from pathlib import Path


BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]


def clone_function():
    if sys.platform != 'darwin':
        return None
    try:
        function = ctypes.CDLL(None, use_errno=True).clonefile
        function.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_int)
        function.restype = ctypes.c_int
        return function
    except AttributeError:
        return None


CLONE = clone_function()


def copy_asset(source, target):
    """Independent files; try APFS COW clone, never hard-link or overwrite."""
    if target.exists():
        raise FileExistsError(f'Refuse to overwrite snapshot/restore target {target}')
    if CLONE is not None:
        if CLONE(os.fsencode(source), os.fsencode(target), 0) == 0:
            return 'macos_clonefile_copy_on_write'
        if target.exists():
            raise FileExistsError(f'Failed clone left a target; preserve it without overwrite {target}')
    shutil.copyfile(source, target)
    return 'byte_copy_fallback'


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
    policy_path = BASE / 'Storage/retention-policy.json'
    if policy_path.exists() and not json.loads(policy_path.read_text()).get('automatic_full_snapshot_creation', False):
        raise ValueError('Routine full snapshots disabled by owner storage policy; archive new content once instead')
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
    for model in processing.get('ocr_models', []):
        register(model['path'], model['sha256'])
    for run in processing['runs']:
        if run.get('manifest'):
            register(run['manifest'])
        for page in run.get('page_records', []):
            if page.get('exit_code') != 0:
                continue
            for input_key in ('source', 'source_crop'):
                if page.get(input_key):
                    register(page[input_key], page.get(input_key + '_sha256'))
            output = page.get('output') or page['output_prefix'] + '.txt'
            register(output, page['sha256'])
            if page.get('tsv_output'):
                register(page['tsv_output'], page['tsv_sha256'])
    for path in BASE.rglob('*'):
        if path.is_file() and path.suffix in ('.json', '.md', '.py', '.svg'):
            register(path.relative_to(REPO))

    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    snapshot_id = timestamp.replace(':', '').replace('+00:00', 'Z') + '-' + uuid.uuid4().hex[:8]
    snapshot = destination / snapshot_id
    snapshot.mkdir(mode=0o700)
    records = list(registered.values())
    copy_methods = collections.Counter()
    for row in records:
        target = snapshot / row['path']
        target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        method = copy_asset(REPO / row['path'], target)
        copy_methods[method] += 1
        os.chmod(target, 0o600)
        if target.stat().st_size != row['bytes'] or digest(target) != row['sha256']:
            raise ValueError(f'Snapshot copy mismatch: {row["path"]}')

    restore_evidence = []
    with tempfile.TemporaryDirectory(prefix='restore-audit-', dir=destination) as scratch:
        original, duplicate = Path(scratch) / 'isolation-source', Path(scratch) / 'isolation-copy'
        original.write_bytes(b'original-fixture-before-write')
        isolation_method = copy_asset(original, duplicate)
        if original.stat().st_ino == duplicate.stat().st_ino:
            raise ValueError('Copy is a shared inode, not an independent file')
        original.write_bytes(b'changed-source-fixture')
        if duplicate.read_bytes() != b'original-fixture-before-write':
            raise ValueError('Source write changed copy')
        duplicate.write_bytes(b'changed-copy-fixture')
        if original.read_bytes() != b'changed-source-fixture':
            raise ValueError('Copy write changed source')
        isolation_evidence = {'method': isolation_method, 'distinct_inodes': True,
                              'source_write_isolated': True, 'copy_write_isolated': True}
        extensions = ['.pdf', '.jpg', '.png', '.mp3', '.xlsx', '.txt', '.tsv', '.traineddata']
        if any(r['path'].endswith('.svg') for r in records):
            extensions.append('.svg')
        for extension in extensions:
            candidate = next((r for r in records if r['path'].endswith(extension)), None)
            if not candidate:
                raise ValueError(f'No representative asset for {extension}')
            restored = Path(scratch) / ('restored' + extension)
            copy_asset(snapshot / candidate['path'], restored)
            actual = digest(restored)
            if actual != candidate['sha256']:
                raise ValueError(f'Restore mismatch: {extension}')
            restore_evidence.append({'source': candidate['path'], 'extension': extension,
                                     'sha256': actual, 'restored_bytes': restored.stat().st_size})

    manifest = {'snapshot_id': snapshot_id, 'created_at_utc': timestamp,
                'snapshot_path': str(snapshot), 'files': records,
                'copy_methods': dict(copy_methods), 'copy_isolation': isolation_evidence,
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
              'copy_methods': dict(copy_methods), 'copy_isolation': isolation_evidence,
              'restore_evidence': restore_evidence, 'limitations': manifest['limitations']}
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ('snapshot_id', 'files_verified', 'bytes_verified')}))


if __name__ == '__main__':
    main()
