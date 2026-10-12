#!/usr/bin/env python3
"""Validate research-only groups and local references, not educational validity.

Requires jsonschema==4.25.1. Schema never permits production/gold admission.
Public projection is a pre-submit structural whitelist, not a semantic leak audit.
"""
import argparse
import copy
import hashlib
import json
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from annotation_ranges import annotation_targets, annotation_range_errors

BASE = Path(__file__).resolve().parents[1]
REPO = BASE.parents[1]
SCHEMA = BASE / 'ItemGroups/ItemGroup.schema.json'
SCHEMAS = {'0.1': SCHEMA, '0.2': BASE / 'ItemGroups/ItemGroup-v0.2.schema.json',
           '0.3': BASE / 'ItemGroups/ItemGroup-v0.3.schema.json'}
CONTENT_FORMAT_PREFIXES = (
    'pdf_parsed', 'image_decoded', 'image_rendered', 'png_decoded', 'jpeg_decoded',
    'html_', 'UTF8_HTML_', 'json_parsed', 'json_schema', 'csv_parsed',
    'utf8_text_decoded', 'utf8_dictionary_parsed', 'xlsx_zip_openpyxl',
    'zip_crc_all_members_passed', 'ffprobe_mp3_container',
    'configuration_text_parsed', 'javascript_read', 'javascript_public_client_only',
)


def acquired_content_metadata(row):
    """Conservative eligibility for a content reference, never semantic validity.

    Transport-only, empty, blocked and unparsed bytes remain acquisition records.
    Unknown validation labels require an explicit parser-policy update.
    """
    return (row.get('status') in ('fetched_unreviewed', 'derived_unreviewed') and
            bool(row.get('path')) and type(row.get('bytes')) is int and row['bytes'] > 0 and
            isinstance(row.get('sha256'), str) and len(row['sha256']) == 64 and
            all(c in '0123456789abcdef' for c in row['sha256']) and
            isinstance(row.get('format_validation'), str) and
            row['format_validation'].startswith(CONTENT_FORMAT_PREFIXES))


def validator_for(group):
    version = group.get('contract_version')
    if version not in SCHEMAS:
        raise ValueError(f'Unsupported contract version: {version}')
    schema = json.loads(SCHEMAS[version].read_text())
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


def semantic_errors(group, sources, acquisitions, check_assets=False):
    errors = []

    def require(condition, message):
        if not condition:
            errors.append(message)

    def index(rows, name):
        result = {}
        for row in rows:
            require(row['id'] not in result, f'{name}: duplicate identity {row["id"]}')
            result[row['id']] = row
        return result

    evidence = index(group['evidence'], 'evidence')
    materials = index(group['materials'], 'materials')
    assets = index(group['assets'], 'assets')
    items = index(group['items'], 'items')
    scores = index(group['private_scoring'], 'scoring')
    targets = index(group['targets'], 'targets')

    def walk(value, path='group'):
        if isinstance(value, dict):
            for key, child in value.items():
                if key == 'evidence_ids':
                    require(set(child) <= evidence.keys(), f'{path}: unknown evidence reference')
                walk(child, path + '/' + key)
            if 'status' in value and 'value' in value:
                if value['status'] in ('unknown', 'not_applicable'):
                    require(value['value'] is None, f'{path}: unknown/inapplicable claim has a value')
                else:
                    require(value['value'] is not None and bool(value.get('evidence_ids')),
                            f'{path}: known claim lacks value/evidence')
        elif isinstance(value, list):
            for i, child in enumerate(value):
                walk(child, f'{path}/{i}')
    walk(group)
    for role in ('independent', 'learner_calibration'):
        claim = group['review'][role]
        if claim['status'] == 'verified':
            require(bool(claim['evidence_ids']) and all(
                evidence.get(eid, {}).get('origin', {}).get('kind') == 'source_record'
                for eid in claim['evidence_ids']),
                f'{role}: fixture authorship cannot establish independent/learner evidence')

    for row in evidence.values():
        origin = row['origin']
        if origin['kind'] == 'source_record':
            require(origin['source_id'] in sources, f'{row["id"]}: unknown source')
            aid = origin['acquisition_id']
            acquired = acquisitions.get(aid, {})
            content_ready = acquired_content_metadata(acquired)
            require(content_ready,
                    f'{row["id"]}: source content lacks nonempty parsed acquisition metadata')
            if check_assets and content_ready:
                path = (REPO / acquired['path']).resolve()
                in_cache = (REPO / 'build').resolve() in path.parents
                require(in_cache and path.is_file(), f'{row["id"]}: missing/outside-cache source content')
                if in_cache and path.is_file():
                    payload = path.read_bytes()
                    require(len(payload) == acquired['bytes'] and
                            hashlib.sha256(payload).hexdigest() == acquired['sha256'],
                            f'{row["id"]}: source content size/digest mismatch')
            if origin['source_id'] in sources:
                require(aid in sources[origin['source_id']].get('acquisition_ids', []),
                        f'{row["id"]}: acquisition belongs to a different source')

    slots = {}
    for material in materials.values():
        index(material['blocks'], material['id'] + '/blocks')
        for block in material['blocks']:
            if block['kind'] == 'slot':
                sid = block['slot_id']
                require(sid not in slots, f'slot: duplicate {sid}')
                slots[sid] = material['id']
            elif block['kind'] == 'asset':
                require(block['asset_id'] in assets, f'{material["id"]}: unknown asset')
    uses = []
    for item in items.values():
        require(set(item['material_ids']) <= materials.keys(), f'{item["id"]}: unknown material')
        require(set(item['target_ids']) <= targets.keys(), f'{item["id"]}: unknown target')
        for sid in item['slot_ids']:
            require(sid in slots and slots[sid] in item['material_ids'],
                    f'{item["id"]}: slot outside referenced material')
            uses.append(sid)
        score = scores.get(item['scoring_id'])
        require(score is not None and item['id'] in score['item_ids'],
                f'{item["id"]}: scoring does not refer back to item')
        response = item['response']
        if group['contract_version'] in ('0.2', '0.3'):
            scope = item['response_scope']
            require(set(scope['slot_ids']) == set(item['slot_ids']),
                    f'{item["id"]}: response scope does not bind the item slots')
            if scope['kind'] == 'slot_only':
                require(bool(scope['slot_ids']) and response['kind'] == 'text',
                        f'{item["id"]}: slot-only response lacks text slots')
            elif scope['kind'] == 'whole_response':
                require(not scope['slot_ids'], f'{item["id"]}: non-slot response has slots')
            if scope['kind'] == 'option_ids':
                require(response['kind'] in ('choice', 'matching', 'ordering'),
                        f'{item["id"]}: option scope on nonoption response')
            if scope['kind'] == 'whole_response':
                require(response['kind'] in ('text', 'writing', 'translation', 'speaking', 'interaction'),
                        f'{item["id"]}: whole-response scope on option response')
            if scope['kind'] == 'annotation_ranges':
                require(response['kind'] == 'span_annotation' and not item['slot_ids'],
                        f'{item["id"]}: annotation scope must bind literal blocks, not slots')
            if scope['kind'] != 'unknown':
                require(bool(scope['evidence_ids']), f'{item["id"]}: response scope lacks evidence')
        if response['kind'] == 'span_annotation':
            require(item['response_scope']['kind'] == 'annotation_ranges',
                    f'{item["id"]}: annotation response lacks explicit annotation scope')
            _, annotation_errors = annotation_targets(group, item)
            errors.extend(f'{item["id"]}: {message}' for message in annotation_errors)
        for name in ('options', 'right_options', 'elements'):
            if name in response:
                index(response[name], item['id'] + '/' + name)
        if response.get('min_words') is not None and response.get('max_words') is not None:
            require(response['min_words'] <= response['max_words'], f'{item["id"]}: reversed word limits')
    require(set(uses) == slots.keys() and len(uses) == len(set(uses)),
            'Slots must each bind exactly one item; no dropped/duplicated gaps')

    expected_response = {'choice': 'choice', 'text': 'text', 'coupled_text': 'text',
                         'segmented': 'text', 'matching': 'matching', 'ordering': 'ordering'}
    for score in scores.values():
        bound = score['item_ids']
        require(set(bound) <= items.keys(), f'{score["id"]}: unknown scoring item')
        if not set(bound) <= items.keys():
            continue
        require(all(items[i]['scoring_id'] == score['id'] for i in bound),
                f'{score["id"]}: mismatched item/scoring association')
        kind = score['kind']
        if group['contract_version'] in ('0.2', '0.3') and kind in ('text', 'coupled_text', 'segmented'):
            policy = score['answer_policy']
            if policy['coverage'] != 'unknown':
                require(bool(policy['evidence_ids']), f'{score["id"]}: coverage lacks evidence')
            if policy['adjudication'] == 'exact_documented_forms':
                require(policy['coverage'] == 'exhaustive_documented',
                        f'{score["id"]}: reference/unknown answers cannot reject unmatched strings')
                require(all(items[i]['response_scope']['kind'] != 'unknown' for i in bound),
                        f'{score["id"]}: exact matching has unknown response scope')
            seen_mappings = set()
            for mapping in score['source_key_mappings']:
                mid = mapping['item_id']
                require(mid in bound, f'{score["id"]}: source key mapping outside scored items')
                identity = (mid, mapping['source_key_form'])
                require(identity not in seen_mappings, f'{score["id"]}: duplicate source key mapping')
                seen_mappings.add(identity)
                original, form, span = mapping['source_key_form'], mapping['response_form'], mapping['source_span']
                operation = mapping['operation']
                if operation == 'unresolved':
                    require(form is None and span is None, f'{score["id"]}: unresolved mapping has fabricated response')
                    require(policy['adjudication'] != 'exact_documented_forms',
                            f'{score["id"]}: unresolved source key cannot use exact matching')
                elif operation == 'identity':
                    require(form == original and span is None, f'{score["id"]}: identity mapping changes source key')
                else:
                    require(span is not None and 0 <= span[0] < span[1] <= len(original),
                            f'{score["id"]}: invalid source key codepoint span')
                    if span is not None and 0 <= span[0] < span[1] <= len(original):
                        require(original[span[0]:span[1]] == form,
                                f'{score["id"]}: extracted form disagrees with source key span')
                    require(mid in items and items[mid]['response_scope']['kind'] == 'slot_only',
                            f'{score["id"]}: span extraction without slot-only response')
                if kind == 'text' and form is not None:
                    require(form in score['accepted_forms'], f'{score["id"]}: mapped form not in documented forms')
        if kind in expected_response:
            require(all(items[i]['response']['kind'] == expected_response[kind] for i in bound),
                    f'{score["id"]}: response/scoring kind mismatch')
        if kind in ('choice', 'text', 'segmented', 'ordering', 'rubric'):
            require(len(bound) == 1, f'{score["id"]}: scoring kind requires one item')
        if kind == 'coupled_text':
            require(len(bound) >= 2 and all(len(t) == len(bound) for t in score['accepted_tuples']),
                    f'{score["id"]}: legal tuple arity mismatch')
        elif kind == 'choice':
            options = {o['id'] for o in items[bound[0]]['response'].get('options', [])}
            require(set(score['accepted_option_ids']) <= options, f'{score["id"]}: unknown correct option')
            if items[bound[0]]['response'].get('selection') == 'single':
                require(len(score['accepted_option_ids']) == 1, f'{score["id"]}: single choice has multiple correct options')
        elif kind == 'ordering':
            elements = {o['id'] for o in items[bound[0]]['response'].get('elements', [])}
            require(all(set(order) == elements and len(order) == len(elements)
                        for order in score['accepted_orders']), f'{score["id"]}: incomplete ordering')
        elif kind == 'matching':
            pairs = score['accepted_pairs']
            require({p['left_item_id'] for p in pairs} == set(bound) and len(pairs) == len(bound),
                    f'{score["id"]}: missing/duplicate left matching item')
            for pair in pairs:
                item = items.get(pair['left_item_id'])
                require(item is not None and pair['right_option_id'] in {
                    o['id'] for o in item['response'].get('right_options', [])},
                    f'{score["id"]}: unknown matching option')
            if any(not items[i]['response'].get('reuse', True) for i in bound):
                require(len({p['right_option_id'] for p in pairs}) == len(pairs),
                        f'{score["id"]}: forbidden right-option reuse')
        elif kind == 'segmented':
            index(score['segments'], score['id'] + '/segments')
            marks = [s['possible_source_marks']['value'] for s in score['segments']]
            total = score['possible_source_marks']['value']
            if total is not None and all(m is not None for m in marks):
                require(abs(sum(marks) - total) < 1e-9, f'{score["id"]}: segment marks disagree with total')
        elif kind == 'span_sets':
            require(len(bound) == 1 and items[bound[0]]['response']['kind'] == 'span_annotation',
                    f'{score["id"]}: annotation scoring must bind one annotation item')
            if len(bound) == 1 and items[bound[0]]['response']['kind'] == 'span_annotation':
                policy = score['answer_policy']
                require(policy['coverage'] != 'unknown' and bool(policy['evidence_ids']),
                        f'{score["id"]}: unknown annotation key must remain unknown scoring')
                if policy['adjudication'] == 'exact_documented_forms':
                    require(policy['coverage'] == 'exhaustive_documented',
                            f'{score["id"]}: reference-only ranges cannot reject all alternatives')
                seen_sets = set()
                for candidate in score['accepted_sets']:
                    errors.extend(f'{score["id"]}: {message}' for message in
                                  annotation_range_errors(group, items[bound[0]], candidate))
                    identity = tuple(sorted((r['material_id'], r['block_id'], r['start'], r['end'])
                                            for r in candidate))
                    require(identity not in seen_sets, f'{score["id"]}: duplicate unordered annotation answer set')
                    seen_sets.add(identity)
        elif kind == 'rubric':
            require(all(items[i]['response']['kind'] in ('writing', 'translation', 'speaking', 'interaction')
                        for i in bound), f'{score["id"]}: rubric applied to nonproductive response')
            dimensions = index(score['dimensions'], score['id'] + '/dimensions')
            bands = set()
            for dimension in dimensions.values():
                for band in dimension['bands']:
                    require(band['id'] not in bands and band['minimum_marks'] <= band['maximum_marks'],
                            f'{score["id"]}: duplicate/reversed rubric band')
                    bands.add(band['id'])
            for example in score['scored_examples']:
                require(set(example['assigned_band_ids']) <= bands, f'{score["id"]}: unknown scored-example band')

    for asset in assets.values():
        transcript = asset['transcript_material_id']
        require(transcript is None or transcript in materials and materials[transcript]['role'] == 'transcript',
                f'{asset["id"]}: transcript association invalid')
        if asset['availability'] == 'not_acquired':
            require(asset['private_locator'] is None and asset['sha256'] is None,
                    f'{asset["id"]}: unacquired asset has fabricated location/digest')
        else:
            require(bool(asset['private_locator']) and bool(asset['sha256']),
                    f'{asset["id"]}: acquired asset lacks location/digest')
            if check_assets and asset['private_locator'] and asset['sha256']:
                path = (REPO / asset['private_locator']).resolve()
                require((REPO / 'build').resolve() in path.parents and path.is_file(),
                        f'{asset["id"]}: missing/outside-cache asset')
                if (REPO / 'build').resolve() in path.parents and path.is_file():
                    require(hashlib.sha256(path.read_bytes()).hexdigest() == asset['sha256'],
                            f'{asset["id"]}: asset digest mismatch')

    admin = group['administration']
    index(admin['supports'], 'supports')
    for support in admin['supports']:
        require(set(support['reveals_related_item_ids']) <= items.keys(), 'Support references unknown item')
    for segment in admin['media_segments']:
        asset = assets.get(segment['asset_id'])
        require(asset is not None and asset['media_type'] in ('audio', 'video'), 'Media segment references nonmedia asset')
        require(set(segment['item_ids']) <= items.keys(), 'Media segment references unknown item')
        require(segment['start_seconds'] < segment['end_seconds'], 'Media segment interval reversed/empty')
        if asset and asset['duration_seconds'] is not None:
            require(segment['end_seconds'] <= asset['duration_seconds'], 'Media segment exceeds duration')
    if admin['mode'] in ('diagnostic', 'ranked'):
        require(admin['submission_boundary'] == 'whole_group' and
                admin['feedback_release'] in ('after_group_submit', 'not_available'),
                'Unassisted diagnostic/ranked group cannot release per-item feedback')
        require(not admin['later_related_items_count_as_unassisted'], 'Exposure cannot count as unassisted evidence')
        require(all(not s['reveals_related_item_ids'] or s['release'] == 'after_group_submit'
                    for s in admin['supports']), 'Pre-submit support reveals diagnostic answers')
        require(all(materials[m]['role'] != 'transcript' for item in items.values()
                    for m in item['material_ids'] if m in materials), 'Diagnostic task exposes transcript')
    return errors


def pre_submit_projection(group):
    """No private source locator, scoring, hints, transcript or scored examples."""
    result = copy.deepcopy({
        'id': group['id'], 'group_version': group['group_version'],
        'contract_version': group['contract_version'], 'kind': group['kind'],
        'materials': [{k: material[k] for k in ('id', 'version', 'language', 'blocks')}
                      for material in group['materials'] if material['role'] == 'stimulus'],
        'items': [{**{k: item[k] for k in ('id', 'version', 'instruction', 'material_ids', 'slot_ids')},
                   'response': {k: v for k, v in item['response'].items() if k in
                                ('kind', 'selection', 'options', 'right_options', 'reuse',
                                 'extra_options_allowed', 'elements', 'max_words', 'min_words',
                                 'word_count_rule', 'requirements')}} for item in group['items']],
        'administration': {k: group['administration'][k] for k in
                           ('mode', 'submission_boundary', 'return_to_items', 'feedback_release')},
    })
    if group['contract_version'] in ('0.2', '0.3'):
        for projected, item in zip(result['items'], group['items']):
            projected['response_scope'] = {k: copy.deepcopy(item['response_scope'][k])
                                           for k in ('kind', 'slot_ids')}
            if item['response']['kind'] == 'span_annotation':
                projected['response'].update({k: copy.deepcopy(item['response'][k]) for k in
                                             ('coordinate_unit', 'normalization', 'surface', 'render_as',
                                              'target_blocks', 'min_ranges', 'max_ranges', 'overlap_policy')})
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('groups', type=Path, nargs='*')
    parser.add_argument('--check-assets', action='store_true')
    args = parser.parse_args()
    sources = {r['id']: r for r in json.loads((BASE / 'Registry/sources.json').read_text())['sources']}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    paths = args.groups or sorted((BASE / 'ItemGroups/Fixtures').glob('*.json'))
    if not paths:
        parser.error('No groups supplied')
    reports = []
    for path in paths:
        try:
            group = json.loads(path.read_text())
            validator = validator_for(group)
            errors = [f'{"/".join(map(str, e.absolute_path))}: {e.message}'
                      for e in validator.iter_errors(group)]
            if not errors:
                errors += semantic_errors(group, sources, acquisitions, args.check_assets)
            incomplete = {} if errors else {
                'unacquired_asset_ids': [a['id'] for a in group['assets'] if a['availability'] != 'acquired'],
                'unknown_scoring_ids': [s['id'] for s in group['private_scoring'] if s['kind'] == 'unknown'],
                'independent_review_status': group['review']['independent']['status'],
                'learner_calibration_status': group['review']['learner_calibration']['status'],
                'answer_coverage_unrecorded': group['contract_version'] == '0.1',
                'nonexhaustive_or_unknown_score_ids': [s['id'] for s in group['private_scoring']
                    if s.get('answer_policy', {}).get('coverage') in ('reference_examples_only', 'unknown')],
                'unknown_response_scope_ids': [i['id'] for i in group['items']
                    if i.get('response_scope', {}).get('kind') == 'unknown'],
                'unresolved_asset_solve_role_ids': sorted({block['asset_id']
                    for material in group['materials'] for block in material['blocks']
                    if block['kind'] == 'asset' and block['required_to_solve'] is None}),
            }
            reports.append({'path': str(path), 'structure_valid': not errors, 'errors': errors,
                            'incomplete_evidence': incomplete,
                            'production_admission': False,
                            'limitation': 'Research structure only; no quality, rights, gold, calibration or production validation'})
        except (OSError, ValueError) as exc:
            reports.append({'path': str(path), 'structure_valid': False, 'errors': [str(exc)]})
    print(json.dumps({'groups': reports}, ensure_ascii=False, indent=2))
    raise SystemExit(0 if all(r['structure_valid'] for r in reports) else 1)


if __name__ == '__main__':
    main()
