#!/usr/bin/env python3
"""Restore a selected historical version to a fresh file, with a SHA check."""
import argparse
import json
from pathlib import Path
from snapshot_research_assets import BASE, copy_asset, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot-id', required=True)
    parser.add_argument('--asset', required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    registry = json.loads((BASE / 'Storage/local-snapshots.json').read_text())
    snapshot = next(s for s in registry['snapshots'] if s['snapshot_id'] == args.snapshot_id)
    manifest_path = Path(snapshot['manifest_path'])
    if digest(manifest_path) != snapshot['manifest_sha256']:
        raise ValueError('Historical manifest changed')
    manifest = json.loads(manifest_path.read_text())
    row = next(r for r in manifest['files'] if r['path'] == args.asset)
    relative = Path(row['path'])
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Nonportable asset identity')
    if snapshot.get('storage_representation') == 'content_addressed_archive':
        archive = next(a for a in registry['content_archives'] if a['archive_id'] == snapshot['archive_id'])
        index_path = Path(archive['index_path'])
        if digest(index_path) != archive['index_sha256']:
            raise ValueError('Archive index differs')
        index = json.loads(index_path.read_text())
        member = next(s for s in index['snapshots'] if s['snapshot_id'] == args.snapshot_id)
        obj = next(o for o in index['objects'] if o['sha256'] == row['sha256'])
        if member['manifest_sha256'] != snapshot['manifest_sha256'] or obj['bytes'] != row['bytes']:
            raise ValueError('Historical archive binding differs')
        source = Path(archive['archive_path']) / 'objects' / row['sha256']
    else:
        source = Path(snapshot['snapshot_path']) / relative
    if source.is_symlink() or source.stat().st_size != row['bytes'] or digest(source) != row['sha256']:
        raise ValueError('Preserved asset differs')
    destination = args.destination.expanduser().absolute()
    if destination.exists() or destination.is_symlink():
        raise ValueError('Never overwrite an existing restoration destination')
    destination.parent.mkdir(parents=True, exist_ok=True)
    copy_asset(source, destination)
    if digest(destination) != row['sha256'] or destination.stat().st_ino == source.stat().st_ino:
        raise ValueError('Independent restoration failed')
    print(json.dumps({'snapshot_id': args.snapshot_id, 'asset': row['path'], 'destination': str(destination),
                      'sha256': row['sha256'], 'bytes': row['bytes'], 'independent_restored_file': True}))


if __name__ == '__main__':
    main()
