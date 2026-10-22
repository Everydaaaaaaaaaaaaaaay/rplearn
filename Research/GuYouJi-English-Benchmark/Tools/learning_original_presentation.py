"""Apply explicitly reviewed option labels without changing frozen manuscripts."""
import copy
import hashlib
import json


def digest(value):
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'))
    return hashlib.sha256(raw.encode()).hexdigest()


def student_input(unit):
    return dict(material=unit['originalGroup']['material'], questions=[dict(
        id=q['id'], type=q['type'], prompt=q['prompt'], instruction=q['instruction'],
        options=q.get('options'), audio=q.get('audio', {}).get('assetId'),
        images=q.get('materialImages', [])) for q in unit['questions']])


def apply_option_labels(manifest, revisions):
    result = copy.deepcopy(manifest)
    if revisions['version'] != 1:
        raise ValueError('Unsupported presentation revision')
    revised_ids = []
    for revision in revisions['units']:
        uid = revision['unitId']
        entries = [e for e in result['units'] if e['unit']['id'] == uid]
        if len(entries) != 1 or uid in revised_ids:
            raise ValueError('Missing or duplicate revised unit: ' + uid)
        entry = entries[0]
        unit = entry['unit']
        if (unit['version'] != revision['fromVersion']
                or digest(unit) != revision['baseContentHash']
                or entry['contentHash'] != revision['baseContentHash']
                or digest(student_input(unit)) != revision['baseStudentInputHash']
                or entry['studentInputHash'] != revision['baseStudentInputHash']
                or revision['toVersion'] != revision['fromVersion'] + 1):
            raise ValueError('Reviewed base changed: ' + uid)
        labels = revision['optionLabels']
        material = unit['originalGroup']['material']
        for question in unit['questions']:
            if (question['type'] != 'choice'
                    or {o['id'] for o in question['options']} != set(labels)):
                raise ValueError('Reviewed option set changed: ' + uid)
            for option in question['options']:
                label = labels[option['id']]
                # Full text must remain verbatim in the shared reading material;
                # the explicit label must identify its existing heading/name.
                if (option['text'] not in material
                        or not option['text'].startswith(label + ' ')):
                    raise ValueError('Option description/name binding changed: ' + uid)
                option['text'] = label
        unit['version'] = revision['toVersion']
        unit['authorship']['reviewedAt'] = revisions['reviewedAt']
        unit['authorship']['reviewNotes'] += ' ' + revisions['reviewNotes']
        entry['authoredPayloadSHA256'] = digest(dict(
            frozenAuthoredPayloadSHA256=entry['authoredPayloadSHA256'],
            presentationRevision=revision, reviewedAt=revisions['reviewedAt'],
            reviewNotes=revisions['reviewNotes']))
        entry['contentHash'] = digest(unit)
        entry['studentInputHash'] = digest(student_input(unit))
        revised_ids.append(uid)
    batch = revisions['publicationBatch']
    if any(b['id'] == batch for b in result['batches']):
        raise ValueError('Presentation publication batch already exists')
    result['batches'].append(dict(id=batch, unitIds=revised_ids))
    return result
