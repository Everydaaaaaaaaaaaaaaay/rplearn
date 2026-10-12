#!/usr/bin/env python3
"""Compute candidate text features using explicit boundaries and pinned CMUdict.

Flesch/FK arithmetic is a text feature, never Lexile, CEFR or Chinese grade.
Unknown words, draft text/boundaries and nonprose suppress formula outputs.
CMUdict: Carnegie Mellon University, BSD terms in its accompanying LICENSE.
"""
import argparse
import hashlib
import json
import re
import unicodedata
from collections import defaultdict
from pathlib import Path


DICT_SHA = '81917843c7f44ce2b094ac63873c2c7a4cf802040792c455ba3ca406891c3d22'
LICENSE_SHA = 'bd4ce8e44170a5f9f481310ca85c51de3c4f851a65e679b40e603b143bd3542a'
COMMIT = '74790861f652b15e4ac49015a90074ad62a27690'
WORDS = re.compile(r"[^\W\d_]+(?:['’][^\W\d_]+)*|\d+(?:[.,]\d+)*", re.UNICODE)


def load_dictionary(path, license_path):
    for file, expected in ((path, DICT_SHA), (license_path, LICENSE_SHA)):
        if hashlib.sha256(file.read_bytes()).hexdigest() != expected:
            raise ValueError('Unreviewed dictionary/license identity')
    result = defaultdict(set)
    for line in path.read_text().splitlines():
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        fields = line.split()
        headword = re.sub(r'\(\d+\)$', '', fields[0])
        count = sum(phone[-1:] in ('0', '1', '2') for phone in fields[1:])
        if count > 0:
            result[headword].add(count)
    return dict(result)


def profile(record, dictionary):
    required = {'text', 'text_review_status', 'prepared_kind', 'sentence_ranges',
                'boundary_review_status', 'preparation_note', 'evidence'}
    if not isinstance(record, dict) or set(record) != required:
        raise ValueError('Input must contain exactly the documented preparation fields')
    text = record['text']
    if not isinstance(text, str) or not text.strip():
        raise ValueError('Empty or non-string text')
    if record['text_review_status'] not in ('verified', 'provisional', 'unknown') or record[
            'boundary_review_status'] not in ('verified', 'provisional', 'unknown'):
        raise ValueError('Invalid review status')
    if record['prepared_kind'] not in ('conventional_prose', 'gapped_text', 'table',
            'poetry', 'dialogue_script', 'test_items', 'unknown'):
        raise ValueError('Unknown preparation kind')
    if any(not isinstance(record[key], str) or not record[key].strip()
           for key in ('preparation_note', 'evidence')):
        raise ValueError('Preparation rationale/evidence required')
    ranges = record['sentence_ranges']
    if not isinstance(ranges, list) or not ranges:
        raise ValueError('Explicit sentence ranges required; no period-count fallback')
    previous = 0
    for interval in ranges:
        if not isinstance(interval, list) or len(interval) != 2 or any(
                type(x) is not int for x in interval):
            raise ValueError('Ranges must be [start,end] Unicode-codepoint half-open intervals')
        start, end = interval
        if not 0 <= previous <= start < end <= len(text) or text[previous:start].strip():
            raise ValueError('Overlapping/reversed/out-of-bounds ranges or omitted nonwhitespace')
        if not WORDS.search(text[start:end]):
            raise ValueError('Sentence range has no lexical tokens')
        previous = end
    if text[previous:].strip():
        raise ValueError('Uncovered trailing text')
    tokens = WORDS.findall(text)
    word_keys = [unicodedata.normalize('NFC', t).replace('’', "'").casefold() for t in tokens]
    unknown = sorted({key for key in word_keys if key not in dictionary})
    known = [dictionary[key] for key in word_keys if key in dictionary]
    low, high = sum(min(v) for v in known), sum(max(v) for v in known)
    blocked = []
    if record['prepared_kind'] != 'conventional_prose':
        blocked.append('Nonprose/uncertain preparation; no formula interpretation')
    if record['text_review_status'] != 'verified' or record['boundary_review_status'] != 'verified':
        blocked.append('Draft text or sentence boundaries; no accepted formula output')
    if re.search(r'_{2,}|<slot|\{\{', text):
        blocked.append('Visible gap/template syntax; no prose formula output')
    if unknown:
        blocked.append('Unknown syllables; no guessed one-syllable or heuristic fallback')
    count, sentences = len(tokens), len(ranges)
    formulas = None
    if not blocked:
        asl = count / sentences
        formulas = {'flesch_reading_ease_variant_envelope': [
            206.835 - 1.015 * asl - 84.6 * high / count,
            206.835 - 1.015 * asl - 84.6 * low / count],
            'flesch_kincaid_us_grade_feature_variant_envelope': [
                .39 * asl + 11.8 * low / count - 15.59,
                .39 * asl + 11.8 * high / count - 15.59]}
    return {'method_version': 'readability-research-0.1',
            'dictionary_commit': COMMIT, 'dictionary_sha256': DICT_SHA,
            'license_sha256': LICENSE_SHA,
            'attribution': 'CMUdict, Copyright Carnegie Mellon University; BSD conditions apply',
            'text_sha256': hashlib.sha256(text.encode()).hexdigest(),
            'tokenization': 'Unicode letters; internal apostrophes one token; hyphen-separated; numeric units unresolved unless dictionary-covered',
            'sentence_count_basis': 'Caller-supplied Unicode-codepoint half-open spans; coverage checked, linguistic boundary review not established by code',
            'word_tokens': count, 'sentence_ranges_count': sentences,
            'covered_syllable_variant_envelope': [low, high],
            'unknown_word_keys': unknown, 'blocked_formula_reasons': blocked,
            'formula_features': formulas, 'chinese_grade_alignment': 'not_established',
            'cefr_alignment': 'not_established', 'lexile_measure': None,
            'limitations': ['Variant envelope is not a statistical confidence interval',
                'Pronunciation choice depends on context/accent; no POS/sense disambiguation',
                'Not guaranteed to reproduce Word tokenization or any other analyzer',
                'Short text features can be unstable; no minimum length is a challenge-design rule',
                'No clipping or rounding into school-stage labels',
                'Text-only features omit questions, options, visuals, support, task demand and learner ability']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--dictionary', type=Path, required=True)
    parser.add_argument('--license', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    cache = Path(__file__).resolve().parents[3] / 'build'
    if cache.resolve() not in output.parents:
        parser.error('Prepared text feature reports must remain in ignored build/')
    dictionary = load_dictionary(args.dictionary, args.license)
    result = profile(json.loads(args.input.read_text()), dictionary)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({k: result[k] for k in ('word_tokens', 'sentence_ranges_count',
        'unknown_word_keys', 'blocked_formula_reasons', 'formula_features')}))


if __name__ == '__main__':
    main()
