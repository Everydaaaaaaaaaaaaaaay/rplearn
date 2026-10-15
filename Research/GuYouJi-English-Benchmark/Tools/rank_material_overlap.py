#!/usr/bin/env python3
"""Nominate lexical-overlap reviews beyond the existing fivegram screen.

English content-word overlap is a queue heuristic, not a semantic classifier.
Short/Chinese-only views, missing visuals and paraphrases may remain undetected.
No source-family merge, answer transfer or independence claim is automated.
"""
import argparse
import json
import math
import re
from collections import Counter
from itertools import combinations
from pathlib import Path

from grade_mode_evidence import BASE, REPO, evidence, load_ref
from audit_school_material_families import digest
from audit_image_transcribed_materials import continuation_ancestors, transcribed_views

STOP_WORDS = frozenset('''a an the and or but if so as at by for from in into of off on onto
out over per to up upon via with without is am are was were be been being do does did have
has had having can could may might must shall should will would this that these those i me
my mine myself you your yours yourself he him his himself she her hers herself it its itself
we us our ours ourselves they them their theirs themselves who whom whose which what when
where why how all any both each either few many more most much neither no none not only
other same some such than too very also just even then there here now because after before
once while during until since about against through between under again further'''.split())
MANIFEST = BASE / 'FirstRelease/Sampling/baseline-final-reading-image-views-v0.1.json'
AUDIT = REPO / 'build/english-benchmark-research-20261012/baseline-final-reading-image-audit20261015ab-v0.1.json'
QUEUE = BASE / 'FirstRelease/Sampling/material-screen-queue-v0.22.json'


def reference(path):
    return {'path': str(path.relative_to(BASE) if path.is_relative_to(BASE) else path.relative_to(REPO)),
            'sha256': digest(path.read_text())}


def current_bodies():
    """Reconstruct the frozen queue0.22 base; later corrections layer separately.

    Use audit_material_view_corrections.corrected_bodies for the active repaired
    view; retaining this base keeps the earlier English report reproducible.
    """
    manifest = json.loads(MANIFEST.read_text())
    bodies, records, _ = continuation_ancestors(manifest)
    new_records, new, _ = transcribed_views(manifest)
    if set(bodies) & set(new):
        raise ValueError('Repeated source identity')
    bodies.update(new)
    queue = json.loads(QUEUE.read_text())
    if load_ref(queue['current_audit']) != AUDIT:
        raise ValueError('Current audit is not the inventory entry point')
    audit = json.loads(AUDIT.read_text())
    if len(bodies) != audit['material_count_total'] or len(bodies) != queue['screened_group_records'] or new_records != audit['records']:
        raise ValueError('Current source-view inventory differs from frozen audit')
    return bodies, records + new_records


def content_tokens(text):
    return {word for word in re.findall('[a-z]+', text.lower()) if len(word) > 2 and word not in STOP_WORDS}


def nominate(bodies):
    tokens = {key: content_tokens(text) for key, text in bodies.items()}
    frequency = Counter(word for values in tokens.values() for word in values)
    weights = {word: (math.log((len(bodies) + 1) / (df + 1)) + 1) ** 2 for word, df in frequency.items()}
    norms = {key: sum(weights[word] for word in sorted(values)) for key, values in tokens.items()}
    candidates = []
    eligible = [key for key, values in tokens.items() if len(values) >= 4]
    for left, right in combinations(eligible, 2):
        shared = tokens[left] & tokens[right]
        if len(shared) < 4:
            continue
        overlap = sum(weights[word] for word in sorted(shared))
        cosine = overlap / math.sqrt(norms[left] * norms[right])
        containment = overlap / min(norms[left], norms[right])
        if cosine >= .24 or containment >= .48:
            candidates.append({'left': left, 'right': right, 'weighted_set_cosine': round(cosine, 6),
                               'weighted_set_containment': round(containment, 6), 'shared_content_terms': len(shared),
                               'shared_terms_by_weight': sorted(shared, key=lambda word: (-weights[word], word))[:12]})
    candidates.sort(key=lambda row: (-row['weighted_set_cosine'], -row['weighted_set_containment'], row['left'], row['right']))
    return tokens, eligible, candidates


def audit():
    bodies, _ = current_bodies()
    rows = {row['id']: row for row in evidence()}
    tokens, eligible, candidates = nominate(bodies)
    return {'version': '0.1', 'scope': 'English content-word nomination over existing source material views only',
            'source_view_manifest': reference(MANIFEST), 'source_text_screen': json.loads(QUEUE.read_text())['current_audit'],
            'source_view_inventory': reference(QUEUE),
            'parameters': {'cosine_min': .24, 'containment_min': .48, 'shared_terms_min': 4,
                           'minimum_term_length': 3, 'stop_words_sha256': digest(' '.join(sorted(STOP_WORDS))),
                           'selection': 'at_least4shared AND (cosine OR containment);not calibrated for family truth'},
            'records': [{'group_id': key, 'paper_identity': rows[key]['paper_id'], 'grade': rows[key]['shape']['grade'],
                         'family': rows[key]['shape']['family'], 'normalized_material_sha256': digest(text),
                         'unique_English_content_terms': len(tokens[key]), 'English_nomination_eligible': key in eligible,
                         'frozen_source_necessary_input_complete': rows[key]['necessary_input_complete']}
                        for key, text in bodies.items()],
            'source_view_count': len(bodies), 'English_eligible_view_count': len(eligible),
            'English_eligible_pair_count': len(eligible) * (len(eligible) - 1) // 2,
            'candidate_count': len(candidates), 'candidates': candidates,
            'all_semantic_or_visual_screening_complete': False, 'zero_candidates_implies_independence': False,
            'automatic_family_merge_or_answer_transfer': False, 'model_called': False, 'production_supported': False}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    if (REPO / 'build').resolve() not in args.output.resolve().parents:
        parser.error('Source-derived output must remain in ignored build/')
    result = audit()
    payload = json.dumps(result, ensure_ascii=False, indent=2) + '\n'
    if args.output.exists() and args.output.read_text() != payload:
        raise ValueError('Do not overwrite a different nomination run')
    if not args.output.exists():
        args.output.write_text(payload)
    print(json.dumps({key: result[key] for key in ['source_view_count', 'English_eligible_view_count',
                                                  'English_eligible_pair_count', 'candidate_count']}))
