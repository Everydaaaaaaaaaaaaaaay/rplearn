"""Select the current mutable research run without rewriting completed deliveries."""
import json
from pathlib import Path
from grade_mode_evidence import BASE


def resolve_plan(relative=None):
    if relative is None:
        pointer=BASE/'FirstRelease/ActiveReviewRun.json'
        relative=json.loads(pointer.read_text())['path'] if pointer.exists() else 'FirstRelease/AllLevelsObjectiveRun-2026-10-16.json'
    relative=Path(relative)
    if relative.is_absolute() or '..' in relative.parts:
        raise ValueError('Nonportable run plan')
    path=BASE/relative
    return path,json.loads(path.read_text())
