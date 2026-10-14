"""Bind reviewed visual supplements without promoting incomplete frozen text."""
import hashlib
import json
import struct
from grade_mode_evidence import BASE, load_ref

DEFINITION = BASE / 'FirstRelease/Sampling/public-preview-bundles-v0.1.json'


def check_supplement(request, row):
    definition = {'path': str(DEFINITION.relative_to(BASE)),
                  'sha256': hashlib.sha256(DEFINITION.read_bytes()).hexdigest()}
    if request.get('definition') != definition:
        raise ValueError('Supplement must reference the registered reviewed bundle definition')
    data = json.loads(load_ref(definition).read_text())
    matches = [b for b in data['bundles'] if b['id'] == request.get('bundle_id')]
    if len(matches) != 1:
        raise ValueError('Unknown reviewed supplement bundle')
    bundle = matches[0]
    if bundle['evidence_group_id'] != row['id'] or bundle['source_text'] != row.get('source_text_ref'):
        raise ValueError('Supplement belongs to a different group or frozen source')
    load_ref(bundle['source_text'])
    load_ref(bundle['parent_html'])
    if (bundle['responses'] != row['shape']['responses'] or bundle['options_each'] != row['shape']['options_each'] or
            bundle['student_bundle_complete'] is not True or bundle['source_key_gold']):
        raise ValueError('Bundle completeness/count or non-gold status differs')
    review = json.loads(load_ref(bundle['visual_review']).read_text())
    if review['parent_html'] != bundle['parent_html'] or review['frozen_resource_text'] != bundle['source_text']:
        raise ValueError('Visual review belongs to another parent or frozen text')
    groups = review.get('selected_reading_groups') or [review['selected_reading_group']]
    selected_groups = [group for group in groups if group['group_id'] == row['id']]
    if len(selected_groups) != 1:
        raise ValueError('Visual review lacks a unique group binding')
    selected = selected_groups[0]
    if (selected['group_id'] != row['id'] or selected['all_cards_and_questions_visually_read'] is not True or
            selected['necessary_cards'] != bundle['poster_cards'] or selected['options_each'] != bundle['options_each'] or
            len(selected['source_question_numbers']) != bundle['responses']):
        raise ValueError('Visual review does not cover this complete group')
    required = [asset['image'] for asset in bundle['required_student_assets']]
    if request.get('included_student_assets') != required:
        raise ValueError('All required material/question images must be included with the frozen text')
    reviewed = {r['image']['path']: r for r in review['images']}
    for asset in required + [bundle['header_identity_image']]:
        raw = load_ref(asset).read_bytes()
        if not raw.startswith(b'\x89PNG\r\n\x1a\n'):
            raise ValueError('Visual supplement is not the reviewed PNG')
        image = reviewed[asset['path']]
        if image['image'] != asset or image['visually_reviewed'] is not True or struct.unpack('>II', raw[16:24]) != (image['width'], image['height']):
            raise ValueError('Image or dimensions differ from reviewed source')
    return {'bundle_id': bundle['id'], 'required_student_assets': required,
            'source_text_alone_complete': bundle['source_text_alone_complete'],
            'student_bundle_complete': True, 'independent_answer_gold': False,
            'production_supported': False, 'commercial_admission': False}
