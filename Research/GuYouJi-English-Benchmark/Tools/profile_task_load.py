#!/usr/bin/env python3
"""Count prepared task components; never infer grade, CEFR or student minutes.

Input is an explicit component allocation, not an automatic PDF/OCR parser.
Shared material appears once. Printed labels/Chinese glosses remain separate.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path

TOKENS = re.compile(r"[A-Za-z0-9]+(?:['’\-][A-Za-z0-9]+)*")
ROLES = {'passage', 'material_label', 'instruction', 'prompt', 'option'}


def count(text):
    if not isinstance(text, str):
        raise ValueError('component text must be a string')
    return {'english_digit_tokens': len(TOKENS.findall(text)),
            'han_characters': len(re.findall(r'[\u3400-\u9fff]', text))}


def profile(record):
    identities = set()
    by_role = {r: {'english_digit_tokens': 0, 'han_characters': 0, 'components': 0}
               for r in sorted(ROLES)}
    sentence_lengths = []
    if not record.get('evidence') or not record.get('preparation_note'):
        raise ValueError('evidence and preparation note required')
    rows = record.get('components')
    if not isinstance(rows, list) or not rows:
        raise ValueError('explicit component allocation required')
    for row in rows:
        identity, role = row['id'], row['role']
        if not isinstance(identity, str) or not identity or identity in identities:
            raise ValueError('duplicate/empty component; shared material must appear once')
        identities.add(identity)
        if role not in ROLES:
            raise ValueError('unknown role; answer/author evidence is not student input')
        values = count(row['text'])
        for k, v in values.items():
            by_role[role][k] += v
        by_role[role]['components'] += 1
        if role == 'passage':
            sentences = row.get('sentences')
            if not isinstance(sentences, list) or not sentences or any(not isinstance(s, str) or not s.strip() for s in sentences):
                raise ValueError('passage needs explicitly reviewed sentence units')
            if re.sub(r'\s+', '', ''.join(sentences)) != re.sub(r'\s+', '', row['text']):
                raise ValueError('sentence units omit/change passage content')
            sentence_lengths += [count(s)['english_digit_tokens'] for s in sentences]
    for role in ['passage', 'prompt', 'option']:
        if by_role[role]['components'] == 0:
            raise ValueError('reading specimen missing ' + role)
    item_ids = record.get('item_ids')
    if not isinstance(item_ids, list) or not item_ids or len(set(item_ids)) != len(item_ids):
        raise ValueError('unique complete item ids required')
    if by_role['prompt']['components'] != len(item_ids):
        raise ValueError('one explicit prompt component required per item')
    options = [r for r in rows if r['role'] == 'option']
    if any(r.get('item_id') not in item_ids for r in options):
        raise ValueError('option refers to absent item')
    if any(sum(r['item_id'] == i for r in options) != record['options_each'] for i in item_ids):
        raise ValueError('incomplete per-item option set')
    total = {k: sum(r[k] for r in by_role.values())
             for k in ['english_digit_tokens', 'han_characters']}
    return {'id': record['id'], 'grade': record['grade'], 'origin': record['origin'],
            'input_sha256': hashlib.sha256(json.dumps(record, ensure_ascii=False, sort_keys=True,
                                                     separators=(',', ':')).encode()).hexdigest(),
            'by_role': by_role, 'total_scoped_text': total, 'items': len(item_ids),
            'explicit_passage_sentence_units': len(sentence_lengths),
            'passage_sentence_token_lengths': sentence_lengths,
            'mean_passage_sentence_tokens': sum(sentence_lengths) / len(sentence_lengths),
            'maximum_passage_sentence_tokens': max(sentence_lengths),
            'source_factual_gold': False, 'independent_transcription_or_boundary_review': False,
            'student_minutes': None, 'cefr_or_chinese_grade_inference': None}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[3]
    if (repo / 'build').resolve() not in args.output.resolve().parents:
        parser.error('prepared-source reports must remain in ignored build/')
    data = json.loads(args.input.read_text())
    ids = [r['id'] for r in data['records']]
    if len(set(ids)) != len(ids):
        raise ValueError('duplicate specimen identity')
    result = {'method_version': 'task-load-0.1',
              'input_file_sha256': hashlib.sha256(args.input.read_bytes()).hexdigest(),
              'records': [profile(r) for r in data['records']],
              'token_rule': 'English/digit runs; apostrophe/hyphen compounds one; decimals comma numbers split; labels excluded only by explicit role',
              'limitations': ['Component and sentence allocation supplied by author, not independent gold',
                             'Counts describe selected specimen, not grade distribution or acceptance threshold',
                             'No CEFR/FK/Lexile or student time inference',
                             'Visual layout, emphasis and cognitive task demands require separate review',
                             'Shared material once; options once each; not repeated rereading workload']}
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps([{'id': r['id'], 'body': r['by_role']['passage']['english_digit_tokens'],
                       'prompt': r['by_role']['prompt']['english_digit_tokens'],
                       'options': r['by_role']['option']['english_digit_tokens'],
                       'scoped': r['total_scoped_text']['english_digit_tokens'],
                       'sentences': r['explicit_passage_sentence_units']} for r in result['records']]))


if __name__ == '__main__':
    main()
