#!/usr/bin/env python3
"""Import built-in imagegen records; preserve originals and pending review state.

Input is a JSON array of {id, kind, prompt, references, output_hint} records.
Run from repository root. This never generates or silently approves artwork.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("records", type=Path)
parser.add_argument("--extract", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
manifest = root / "Assets/Stories/Departures/production.json"
production = json.loads(manifest.read_text())
records = {r["id"]: r for r in production["assets"]}
for record in json.loads(args.records.read_text()):
    if record["id"] in records:
        continue
    source = Path(re.search(r"as (/[^\n]+\.png) by default", record["output_hint"])[1])
    raw = root / "Assets/Stories/Departures/raw" / (record["id"] + ".png")
    if raw.exists() and hashlib.sha256(raw.read_bytes()).digest() != hashlib.sha256(source.read_bytes()).digest():
        raise ValueError(f"Conflicting unregistered original: {raw}")
    if not raw.exists():
        temporary = raw.with_suffix('.importing')
        try:
            shutil.copy2(source, temporary)
            temporary.replace(raw)
        finally:
            temporary.unlink(missing_ok=True)
    record.update(raw_path=str(raw.relative_to(root)),
                  raw_sha256=hashlib.sha256(raw.read_bytes()).hexdigest(), status="raw-generated")
    records[record["id"]] = record
    # Persist provenance per completed copy, so interrupted batches resume safely.
    production["assets"] = list(records.values())
    manifest.write_text(json.dumps(production, ensure_ascii=False, indent=2) + "\n")
for record in records.values():
    if record["status"] in {"reference-only", "rejected", "superseded"}:
        continue
    suffix = ".png" if record["kind"] == "sprite" else ".jpg"
    target = root / "App/Resources/StoryArt/Departures" / ("dp_" + record["id"] + suffix)
    raw = root / record["raw_path"]
    if not target.exists():
        if record["kind"] == "sprite":
            if not args.extract:
                continue
            subprocess.run([str(root / "build/art-tools/prepare-story-sprite"), str(raw), str(target), "--exterior-only"], check=True)
        else:
            Image.open(raw).convert("RGB").save(target, quality=92, optimize=True)
    record.update(target_path=str(target.relative_to(root)), sha256=hashlib.sha256(target.read_bytes()).hexdigest())
    if record["status"] == "raw-generated":
        record["status"] = "processed-awaiting-review"
production["assets"] = list(records.values())
manifest.write_text(json.dumps(production, ensure_ascii=False, indent=2) + "\n")
print(f"Registered {len(records)} assets; inspection states preserved")
