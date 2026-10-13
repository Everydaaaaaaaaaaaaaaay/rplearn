#!/usr/bin/env python3
"""Reject source numbers as answers and verify explicitly bound reference mappings."""
import json
import re
import validate_firstrelease_v0_3 as core


def check(private, observations, acquisitions):
    errors = []
    choice_count = 0
    mapped_count = 0
    for group in private['groups']:
        source = observations[group['group_id']]
        choices = source.get('features', {}).get('options_each')
        reference = group.get('published_key_mapping_binding')
        mapping = None
        if reference:
            record = acquisitions[reference['acquisition_id']]
            path = core.REPO / record['path']
            if core.digest(path) != reference['sha256'] or record['sha256'] != reference['sha256']:
                errors.append(group['group_id'] + ': mapping digest differs')
            mapping = json.loads(path.read_text())[reference['field']]
            if not isinstance(mapping, dict):
                errors.append(group['group_id'] + ': expected number-to-answer mapping')
                mapping = None
        if [item['source_number'] for item in group['items']] != source['question_numbers']:
            errors.append(group['group_id'] + ': source item order differs')
        for item in group['items']:
            identity = group['group_id'] + ':' + str(item['source_number'])
            value = item['published_reference_answer']
            if not isinstance(value, str) or not value.strip():
                errors.append(identity + ': missing answer value')
            elif choices:
                choice_count += 1
                allowed = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[:choices]
                if value not in allowed:
                    errors.append(identity + ': answer must be a printed option label, not a question number')
            if mapping is not None:
                mapped_count += 1
                if value != mapping.get(str(item['source_number'])):
                    errors.append(identity + ': reference value differs from bound number-to-answer mapping')
    return {'seed_answer_values_valid': not errors, 'errors': errors,
            'choice_label_values_checked': choice_count, 'explicit_mapped_values_checked': mapped_count,
            'independent_semantic_validation': False,
            'limitation': 'Value types and bound author transcription mappings do not establish original key authenticity or semantic gold.'}
