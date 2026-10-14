#!/usr/bin/env python3
"""Preserve old versions once by SHA before removing duplicate backup payloads.

Keeps latest two full snapshots, every manifest, and unregistered files. Never
changes the working cache. A crash after registration leaves recoverable objects;
rerunning verifies each remaining file before unlinking. --plan is read-only.
"""
import argparse
import datetime
import json
import os
import tempfile
from pathlib import Path
from snapshot_research_assets import copy_asset, digest, BASE, REPO


def atomic_json(path, value):
    temporary = path.with_name(path.name + '.compacting-tmp')
    if temporary.exists():
        raise ValueError('Unresolved previous metadata write: ' + str(temporary))
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n')
    os.replace(temporary, path)


def regular(root, relative):
    path = Path(relative)
    if path.is_absolute() or '..' in path.parts:
        raise ValueError('Nonportable snapshot member')
    target = root / path
    if target.is_symlink() or root not in target.resolve().parents:
        raise ValueError('Unexpected symlink/outside member')
    return target


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--plan', action='store_true')
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    if args.plan == args.apply:
        parser.error('Choose exactly one of --plan or --apply')
    registry_path = BASE / 'Storage/local-snapshots.json'
    registry = json.loads(registry_path.read_text())
    policy = json.loads((BASE / 'Storage/retention-policy.json').read_text())
    keep = policy['retained_recent_full_snapshots']
    if type(keep) is not int or keep < 2 or not policy['delete_duplicate_snapshot_payload_only_after_archive_verification']:
        raise ValueError('Unsafe retention policy')
    snapshots = registry['snapshots']
    older, retained = snapshots[:-keep], snapshots[-keep:]
    roots = {Path(s['snapshot_path']).resolve().parent for s in snapshots}
    if len(roots) != 1:
        raise ValueError('Snapshots do not share one explicit storage root')
    destination = roots.pop()
    if destination == REPO or REPO in destination.parents:
        raise ValueError('Backup destination must be outside the workspace')
    manifests, objects = {}, {}
    logical = entries = 0
    for snapshot in older:
        root = Path(snapshot['snapshot_path']).resolve()
        mp = Path(snapshot['manifest_path']).resolve()
        if root.parent != destination or root not in mp.parents or digest(mp) != snapshot['manifest_sha256']:
            raise ValueError('Snapshot/manifest identity differs')
        manifest = json.loads(mp.read_text())
        if len(manifest['files']) != snapshot['files_verified'] or sum(r['bytes'] for r in manifest['files']) != snapshot['bytes_verified']:
            raise ValueError('Manifest count differs')
        manifests[snapshot['snapshot_id']] = manifest
        for row in manifest['files']:
            path = regular(root, row['path'])
            h = row['sha256']
            if len(h) != 64 or any(c not in '0123456789abcdef' for c in h):
                raise ValueError('Invalid content identity')
            if h in objects and objects[h]['bytes'] != row['bytes']:
                raise ValueError('Digest/size conflict')
            objects.setdefault(h, {'bytes': row['bytes'], 'source': path})
            logical += row['bytes']
            entries += 1
    summary = {'old_snapshots': len(older), 'retained_full_snapshots': len(retained),
               'old_file_entries': entries, 'unique_objects': len(objects),
               'old_logical_bytes': logical, 'unique_bytes': sum(r['bytes'] for r in objects.values()),
               'duplicate_logical_bytes': logical - sum(r['bytes'] for r in objects.values())}
    print(json.dumps({'plan': summary}), flush=True)
    if args.plan:
        return
    archive_id = 'sha256-history-20261015-v1'
    archive = destination / archive_id
    archive.mkdir(exist_ok=True, mode=0o700)
    store = archive / 'objects'
    store.mkdir(exist_ok=True, mode=0o700)
    # Materialize one independent backup object per exact byte identity.
    for i, (h, item) in enumerate(objects.items(), 1):
        target = store / h
        if not target.exists():
            source = item['source']
            if not source.is_file() or source.stat().st_size != item['bytes'] or digest(source) != h:
                raise ValueError('Unique old source changed: ' + str(source))
            copy_asset(source, target)
        if not target.is_file() or target.is_symlink() or target.stat().st_size != item['bytes'] or digest(target) != h:
            raise ValueError('Archive object verification failed')
        os.chmod(target, 0o400)
        if i % 1500 == 0:
            print(json.dumps({'objects_verified': i}), flush=True)
    # Verify every old path BEFORE removing any payload. Already-compacted rows
    # can be resumed from their registered objects without losing version data.
    for snapshot in older:
        root = Path(snapshot['snapshot_path']).resolve()
        for row in manifests[snapshot['snapshot_id']]['files']:
            path = regular(root, row['path'])
            if path.exists():
                if not path.is_file() or path.stat().st_size != row['bytes'] or digest(path) != row['sha256']:
                    raise ValueError('Old member changed; no cleanup allowed: ' + str(path))
            elif snapshot.get('storage_representation') != 'content_addressed_archive':
                raise ValueError('Unregistered missing historical member')
        print(json.dumps({'old_snapshot_verified': snapshot['snapshot_id']}), flush=True)
    # Restoration uses fresh independent copies across representative formats.
    # An older-only version can also be checked with restore_research_asset.py.
    restore_checks = []
    with tempfile.TemporaryDirectory(prefix='archive-restore-', dir=destination) as scratch:
        for suffix in ['.pdf', '.mp3', '.json', '.txt', '.png', '.tsv']:
            candidate = next((r for m in manifests.values() for r in m['files'] if r['path'].endswith(suffix)), None)
            if candidate is None:
                continue
            path = Path(scratch) / ('restored' + suffix)
            copy_asset(store / candidate['sha256'], path)
            if digest(path) != candidate['sha256'] or path.stat().st_ino == (store / candidate['sha256']).stat().st_ino:
                raise ValueError('Independent archive restoration failed')
            restore_checks.append({'path': candidate['path'], 'sha256': candidate['sha256'], 'bytes': candidate['bytes']})
    timestamp = datetime.datetime.now(datetime.timezone.utc).isoformat()
    index = {'archive_id': archive_id, 'created_at_utc': timestamp, 'hash_algorithm': 'sha256',
             'objects': [{'sha256': h, 'bytes': r['bytes']} for h, r in sorted(objects.items())],
             'snapshots': [{'snapshot_id': s['snapshot_id'], 'manifest_path': s['manifest_path'],
                            'manifest_sha256': s['manifest_sha256']} for s in older],
             'summary': summary, 'restore_checks': restore_checks,
             'current_cache_mutations': 0, 'unknown_files_deleted': 0, 'same_host_only': True}
    index_path = archive / 'archive-index.json'
    if index_path.exists():
        previous = json.loads(index_path.read_text())
        if previous['objects'] != index['objects'] or previous['snapshots'] != index['snapshots']:
            raise ValueError('Existing archive has a different membership')
        index = previous
    else:
        atomic_json(index_path, index)
    archive_record = {'archive_id': archive_id, 'archive_path': str(archive), 'index_path': str(index_path),
                      'index_sha256': digest(index_path), 'unique_objects': len(objects),
                      'unique_bytes': summary['unique_bytes'], 'restore_checks': index['restore_checks']}
    existing = registry.setdefault('content_archives', [])
    if not any(a['archive_id'] == archive_id for a in existing):
        existing.append(archive_record)
    elif next(a for a in existing if a['archive_id'] == archive_id) != archive_record:
        raise ValueError('Registered archive differs')
    for snapshot in older:
        snapshot['storage_representation'] = 'content_addressed_archive'
        snapshot['archive_id'] = archive_id
        snapshot['current_independent_full_tree'] = False
        snapshot['historical_copy_isolation_record_not_current_layout'] = True
    for snapshot in retained:
        snapshot['storage_representation'] = 'independent_full_snapshot'
        snapshot['current_independent_full_tree'] = True
    registry['updated_on'] = '2026-10-15'
    registry['status'] = 'two_recent_full_snapshots_plus_verified_deduplicated_historical_archive_same_host_only'
    atomic_json(registry_path, registry)
    # Delete only registered, verified old payloads. Leave every manifest and
    # unknown file untouched. Every member was verified in the preceding pass.
    removed = 0
    for snapshot in older:
        root = Path(snapshot['snapshot_path']).resolve()
        directories = set()
        for row in manifests[snapshot['snapshot_id']]['files']:
            path = regular(root, row['path'])
            if path.exists():
                # Detect a concurrent modification before deletion.
                if path.stat().st_size != row['bytes'] or digest(path) != row['sha256']:
                    raise ValueError('Concurrent member change; preserve it')
                path.unlink()
                removed += 1
                directories.update(p for p in path.parents if p != root and root in p.parents)
        for directory in sorted(directories, key=lambda p: len(p.parts), reverse=True):
            try:
                directory.rmdir()
            except OSError:
                pass
        print(json.dumps({'old_payload_pruned': snapshot['snapshot_id']}), flush=True)
    report = {'observed_on': '2026-10-15', 'archive': archive_record, 'summary': summary,
              'removed_duplicate_tree_file_entries': removed, 'original_manifests_retained': len(older),
              'latest_two_full_trees_untouched': True, 'current_cache_mutations': 0,
              'unknown_files_deleted': 0, 'recovery_from_content_objects_verified': True}
    report_path = REPO / 'build/english-benchmark-research-20261012/snapshot-compaction20261015-v0.1.json'
    if not report_path.exists():
        atomic_json(report_path, report)
    print(json.dumps({'completed': report}), flush=True)


if __name__ == '__main__':
    main()
