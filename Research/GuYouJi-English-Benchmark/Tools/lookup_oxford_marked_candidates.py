#!/usr/bin/env python3
"""Read exact POS candidates plus a validated, explicit homograph-marker overlay.

Never strip digits from user text, stem inflections, select the lowest CEFR label,
infer an unseen sense, or translate these source labels into Chinese grades.
The proprietary source index and overlay remain in private research cache.
"""
import argparse
import hashlib
import json
from pathlib import Path


def identity(entry):
    return (entry['source_list'], entry['pdf_page'], tuple(entry['native_line_numbers']),
            entry['display_headword'], tuple(entry['pos_tags']), entry['level'])


def lookup(index_path, overlay_path, headword, pos):
    data = Path(index_path).read_bytes()
    index_sha = hashlib.sha256(data).hexdigest()
    entries = [entry for source in json.loads(data)['sources'] for entry in source['entries']]
    by_identity = {identity(entry): entry for entry in entries}
    if len(by_identity) != len(entries):
        raise ValueError('duplicate frozen source identity')
    overlay = json.loads(Path(overlay_path).read_text())
    if overlay['base_index_sha256'] != index_sha:
        raise ValueError('overlay does not belong to this frozen source index')
    seen = set()
    marked = []
    for row in overlay['rows']:
        key = identity(row['source_entry'])
        if key not in by_identity or key in seen:
            raise ValueError('overlay source identity absent or duplicated')
        seen.add(key)
        raw = row['source_entry']['display_headword']
        expected = row['orthographic_headword'] + row['homograph_marker'] + row['qualifier_suffix']
        if raw != expected or row['homograph_marker'] not in ('1', '2') or row['marker_visually_checked'] is not True:
            raise ValueError('overlay alters source spelling/qualifier or lacks marker evidence')
        if row['orthographic_headword'] == headword and pos in row['source_entry']['pos_tags']:
            marked.append({'lookup_lane':'explicit_checked_marker_overlay',
                           'orthographic_headword':row['orthographic_headword'],
                           'homograph_marker':row['homograph_marker'],
                           'source_qualifier_suffix':row['qualifier_suffix'],
                           'source_entry':row['source_entry']})
    if len(seen) != overlay['source_entry_count']:
        raise ValueError('overlay header count differs from actual identities')
    exact = [{'lookup_lane':'exact_source_display_headword','source_entry':entry}
             for entry in entries if entry['display_headword'] == headword and pos in entry['pos_tags']]
    # A marked display string requested verbatim may also have a separate spelling key;
    # never duplicate a physical source row in the result.
    candidates = exact + [row for row in marked if identity(row['source_entry']) not in {identity(x['source_entry']) for x in exact}]
    if not candidates:
        status = 'unlisted_in_this_exact_POS_and_marker_lookup_view'
    elif len(candidates) == 1:
        status = 'single_source_wordhead_POS_candidate_not_context_gold'
    else:
        status = 'multiple_source_entries_context_resolution_required'
    return {'headword':headword,'requested_POS':pos,'base_index_sha256':index_sha,
            'candidates':candidates,'candidate_count':len(candidates),'status':status,
            'candidate_levels':sorted({row['source_entry']['level'] for row in candidates}),
            'minimum_or_maximum_level_selected':False,'inflection_or_variant_expansion':False,
            'wordhead_level_is_context_or_Chinese_grade':False,'independent_review':False}


if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--index',type=Path,required=True)
    parser.add_argument('--overlay',type=Path,required=True)
    parser.add_argument('--headword',required=True)
    parser.add_argument('--pos',required=True)
    args=parser.parse_args()
    print(json.dumps(lookup(args.index,args.overlay,args.headword,args.pos),ensure_ascii=False,indent=2))
