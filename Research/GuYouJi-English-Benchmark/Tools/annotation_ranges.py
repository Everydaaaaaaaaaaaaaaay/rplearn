"""Validate literal-block annotation coordinates; no educational scoring inference.

Coordinates refer to unchanged Unicode codepoints in an identified text block,
not concatenated HTML, UTF-16 offsets or filled slot text. Unknown source keys
remain unknown. Text echoes detect a shifted selection with the same label.
"""
import hashlib


def annotation_targets(group, item):
    errors, targets = [], {}
    materials = {m['id']: m for m in group['materials']}
    response = item['response']
    for reference in response['target_blocks']:
        identity = (reference['material_id'], reference['block_id'])
        if identity in targets:
            errors.append('Duplicate annotation block reference')
            continue
        material = materials.get(reference['material_id'])
        if material is None or material['id'] not in item['material_ids']:
            errors.append('Annotation target outside item materials')
            continue
        if material['role'] != 'stimulus':
            errors.append('Annotation target must be a presented stimulus block')
        if material['version'] != reference['material_version']:
            errors.append('Stale annotation material version')
        block = next((b for b in material['blocks'] if b['id'] == reference['block_id']), None)
        if block is None or block['kind'] != 'text':
            errors.append('Annotation target is not an acquired literal text block')
            continue
        text = block['text']
        if hashlib.sha256(text.encode('utf-8')).hexdigest() != reference['text_sha256']:
            errors.append('Annotation literal text digest differs')
        targets[identity] = text
    if response['max_ranges'] is not None and response['min_ranges'] > response['max_ranges']:
        errors.append('Annotation selection bounds reversed')
    return targets, errors


def annotation_range_errors(group, item, ranges):
    """Check proposed learner/author ranges against the same frozen surface.

This does not decide whether a selected word is a noun or is a correct answer.
An empty selection may be a legitimate incomplete attempt if bounds permit it.
"""
    targets, errors = annotation_targets(group, item)
    response = item['response']
    if not isinstance(ranges, list):
        return errors + ['Annotation ranges must be a list']
    if len(ranges) < response['min_ranges'] or (
            response['max_ranges'] is not None and len(ranges) > response['max_ranges']):
        errors.append('Annotation range count outside documented bounds')
    seen, intervals = set(), {}
    for value in ranges:
        if not isinstance(value, dict) or set(value) != {
                'material_id', 'block_id', 'start', 'end', 'selected_text'}:
            errors.append('Annotation range fields incomplete or unrecognised')
            continue
        if not isinstance(value['material_id'], str) or not isinstance(value['block_id'], str):
            errors.append('Annotation block identity must be text')
            continue
        identity = (value['material_id'], value['block_id'])
        text = targets.get(identity)
        start, end = value['start'], value['end']
        if text is None:
            errors.append('Annotation range outside declared target blocks')
            continue
        if type(start) is not int or type(end) is not int or not 0 <= start < end <= len(text):
            errors.append('Annotation codepoint range is empty, reversed or out of bounds')
            continue
        if not isinstance(value['selected_text'], str) or text[start:end] != value['selected_text']:
            errors.append('Annotation selected text disagrees with frozen codepoint slice')
        key = (identity, start, end)
        if key in seen:
            errors.append('Duplicate annotation range')
        seen.add(key)
        for old_start, old_end in intervals.get(identity, []):
            if max(start, old_start) < min(end, old_end):
                errors.append('Overlapping annotation ranges')
        intervals.setdefault(identity, []).append((start, end))
    return errors
