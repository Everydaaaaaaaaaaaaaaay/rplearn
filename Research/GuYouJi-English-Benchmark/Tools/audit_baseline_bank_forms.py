#!/usr/bin/env python3
"""Bind multi-passage grammar, phrase banks and mutually exclusive source variants."""
import argparse
import json
import re
from itertools import combinations
from pathlib import Path
from grade_mode_evidence import BASE, evidence, load_ref
from audit_school_material_families import digest, remove_offsets
from audit_image_transcribed_materials import transcribed_views
from audit_baseline_native_materials import native_views
from audit_baseline_prepared_materials import prepared_views, prior_bodies
from audit_cloze_materials import normalized, shingles
from profile_task_load import count

MANIFEST = BASE / 'FirstRelease/Sampling/baseline-bank-form-views-v0.1.json'


def source_views(manifest):
    sources = {r['id']: r for r in evidence()}
    acquisitions = {r['id']: r for r in json.loads((BASE / 'Registry/acquisitions.json').read_text())['acquisitions']}
    records, bodies, atomic, layouts = [], {}, {}, {}
    for case in manifest['views']:
        row = sources[case['group_id']]
        if row['layer'] != 'baseline_selected117' or row['paper_id'] != case['source_parent_id']:
            raise ValueError('Bank/form parent or source layer differs')
        for identity, ref in [(case['source_parent_id'], case['parent_document']), (case['snapshot_acquisition_id'], case['snapshot'])]:
            a = acquisitions[identity]
            if ref != {'path': a['path'], 'sha256': a['sha256']}:
                raise ValueError('Bank/form source version differs')
            load_ref(ref)
        data = json.loads(load_ref(case['snapshot']).read_text());text = data
        for key in case['page_pointer']:
            text = text[key]
        if digest(text) != case['native_page_sha256']:
            raise ValueError('Frozen bank/form native page changed')
        obs = next(r for r in json.loads(load_ref(case['source_catalogue']).read_text())['groups'] if r['id'] == row['id'])
        if obs['acquisition_id'] != case['source_parent_id'] or obs['grade'] != row['shape']['grade']:
            raise ValueError('Bank/form catalogue binding differs')
        def read(span):
            value = text[span['start_offset']:span['end_offset']]
            if not 0 <= span['start_offset'] < span['end_offset'] <= len(text) or digest(value) != span['sha256']:
                raise ValueError('Changed material/hint/bank/instruction boundary')
            return value
        instruction = read(case['student_instruction'])
        parts, material_records, slots, given = [], [], [], []
        for ordinal, span in enumerate(case['materials'], 1):
            raw = read(span);labels = sorted([e for e in span['excluded_offsets'] if e['role'] == 'blank_label'], key=lambda e:e['start'])
            if span['ordinal'] != ordinal or [e['blank_id'] for e in labels] != span['blank_numbers']:
                raise ValueError('Material blank allocation differs')
            measured = remove_offsets(raw, span['excluded_offsets'], ' ')
            norm = normalized(measured);parts.append(norm)
            atomic[row['id'] + '.material' + str(ordinal)] = norm
            hint_numbers = []
            for hint in span['given_hints']:
                value = read(hint);hint_numbers.append(hint['blank_number'])
                label = next(e for e in labels if e['blank_id'] == hint['blank_number'])
                if not re.fullmatch(r'\([^()]+\)',value) or raw[label['end']:hint['start_offset']-span['start_offset']].strip():
                    raise ValueError('Given hint is not adjacent to its declared blank')
            given += hint_numbers;slots += span['blank_numbers']
            material_records.append({'ordinal':ordinal,'blank_numbers':span['blank_numbers'],'material_sha256':digest(raw),
                                     'normalized_material_sha256':digest(norm),'counts_without_hints_or_blank_labels':count(measured)})
        if slots != obs['question_numbers'] or len(slots) != row['shape']['responses'] or [s['printed_number'] for s in case['response_slots']] != slots:
            raise ValueError('Whole source response sequence differs')
        bank = case['shared_bank']
        if bank:
            source_bank = read(bank)
            if len(bank['entries']) != row['shape']['details']['entries'] or len(set(bank['entries'])) != len(bank['entries']) or any(e not in source_bank for e in bank['entries']):
                raise ValueError('Shared bank entries/phrase boundaries differ')
            if re.sub(r'\s+', ' ', source_bank).strip() != ' '.join(bank['entries']):
                raise ValueError('Bank source sequence differs from reviewed entries')
            if ('只用一次' not in instruction or case['reuse_rule'] != 'once' or
                    case['form_change_explicit'] != ('适当形式' in instruction)):
                raise ValueError('Printed reuse/form policy differs')
            if case['strict_no_form_change_explicit'] and not ('不变形' in instruction or '不得改变' in instruction):
                raise ValueError('Strict no-form-change wording is not printed')
            choice = case['alternative_choice'];d = json.loads(load_ref(choice['snapshot']).read_text());header=d
            for key in choice['pointer']:header=header[key]
            header=header[choice['start_offset']:choice['end_offset']]
            if digest(header) != choice['sha256'] or '任选一题' not in header or choice['required_choice_count'] != 1 or choice['mandatory_responses_across_pair'] != 10:
                raise ValueError('A/B selection policy differs from original heading')
            if choice['alternative_group_id'] != obs['features']['alternative_to'] or choice['alternative_group_id'] == row['id']:
                raise ValueError('Alternative source relationship differs')
        else:
            if len(case['materials']) != row['shape']['details']['materials'] or (row['shape']['details']['subgroup_slots'] is not None and [len(s['blank_numbers']) for s in case['materials']] != row['shape']['details']['subgroup_slots']):
                raise ValueError('Multi-passage source configuration differs')
            if not ('适当的单词' in instruction or '适当的' in instruction or '1 个适当' in instruction):
                raise ValueError('Ungiven one-word source instruction missing')
        for ordinal, slot in enumerate(case['response_slots'],1):
            if slot['ordinal'] != ordinal or slot['material_ordinal'] != next(s['ordinal'] for s in case['materials'] if slot['printed_number'] in s['blank_numbers']):
                raise ValueError('Response assigned to a different material')
            if (slot['given_hint'] is not None) != (slot['printed_number'] in given) or slot['word_limit'] != (None if bank or slot['given_hint'] else 1):
                raise ValueError('Given/ungiven/phrase response policy differs')
            if slot['given_hint'] is not None and slot['given_hint'] != next(h for s in case['materials'] for h in s['given_hints'] if h['blank_number']==slot['printed_number']):
                raise ValueError('Response hint points to a different source word')
        gid=row['id']
        if gid in bodies:raise ValueError('Duplicate bank/form source')
        bodies[gid]=' '.join(parts)
        records.append({'group_id':gid,'paper_identity':row['paper_id'],'source_materials':material_records,
                        'normalized_material_sha256':digest(bodies[gid]),'responses':len(slots),'given_hint_numbers':given,
                        'ungiven_numbers':[n for n in slots if n not in given] if not bank else None,
                        'bank_entry_count':len(bank['entries']) if bank else None,'bank_word_counts':count(read(bank)) if bank else None,
                        'native_spacing_not_repaired':True,'frozen_source_input_state':row['necessary_input_complete'],
                        'independent_gold':False})
        layouts[gid]={'source_shape':row['shape'],'snapshot':case['snapshot'],'materials':material_records,
                      'response_slots':case['response_slots'],'bank_entries':bank['entries'] if bank else None,
                      'reuse_rule':case['reuse_rule'],'form_change_explicit':case['form_change_explicit'],
                      'strict_no_form_change_explicit':case['strict_no_form_change_explicit'],'alternative_choice':case['alternative_choice'],
                      'frozen_source_input_state':row['necessary_input_complete']}
    return records,bodies,atomic,layouts


def ancestor_materials(manifest):
    image_manifest=json.loads(load_ref(manifest['prior_view_manifest']).read_text())
    irecords,ibodies,_=transcribed_views(image_manifest)
    native_manifest=json.loads(load_ref(image_manifest['prior_view_manifest']).read_text());nrecords,nbodies,_=native_views(native_manifest)
    prepared_manifest=json.loads(load_ref(native_manifest['prior_view_manifest']).read_text());precords,pbodies=prepared_views(prepared_manifest)
    old,earliest=prior_bodies(prepared_manifest)
    for layer in [pbodies,nbodies,ibodies]:
        if set(old)&set(layer):raise ValueError('Duplicate ancestor source')
        old.update(layer)
    prior=json.loads(load_ref(manifest['prior_material_audit']).read_text())
    if len(old)!=prior['material_count_total'] or any(digest(old[r['group_id']])!=r['normalized_material_sha256'] for r in prior['records']):
        raise ValueError('Ancestor source normalization changed')
    return old,earliest['records']+precords+nrecords+irecords,prior


def check(request,layouts):
    gid=request.get('evidence_group_id')
    if gid not in layouts or request.get('layout')!=layouts[gid]:raise ValueError('Bank/form material/slot/hint/phrase/alternative policy differs')
    if request.get('requires_complete_student_input',True) and layouts[gid]['frozen_source_input_state'] is not True:
        raise ValueError('Native layout binding does not upgrade unconfirmed full source input')
    if request.get('use_as_verified_answer_gold') or request.get('claim_production_supported'):
        raise ValueError('Source layout is not semantic gold or production support')
    return {'source_bank_form_layout_matches':True,'evidence_group_id':gid,'frozen_source_input_state':layouts[gid]['frozen_source_input_state'],
            'model_called':False,'independent_gold':False,'production_supported':False}


def compare(a,b):
    left,right=shingles(a),shingles(b);jac=len(left&right)/len(left|right) if left|right else 0;con=len(left&right)/min(len(left),len(right)) if left and right else 0;exact=a==b
    return {'exact_normalized_match':exact,'fivegram_jaccard':jac,'fivegram_containment':con,'review_candidate':exact or jac>=.5 or con>=.8}


def audit():
    manifest=json.loads(MANIFEST.read_text());records,new,atomic,_=source_views(manifest);old,old_records,prior=ancestor_materials(manifest)
    if set(old)&set(new):raise ValueError('New group already included')
    bodies=dict(old,**new);comparisons=[]
    for left,right in combinations(bodies,2):
        if left in old and right in old:continue
        comparisons.append({'left':left,'right':right,**compare(bodies[left],bodies[right])})
    total=len(bodies)*(len(bodies)-1)//2
    if total!=prior['pair_count_total']+len(comparisons):raise ValueError('Group-view comparison coverage differs')
    atomic_candidates=[];atomic_pairs=0
    for left,a in atomic.items():
        for right,b in old.items():
            result=compare(a,b);atomic_pairs+=1
            if result['review_candidate']:atomic_candidates.append({'left':left,'right':right,**result})
    for left,right in combinations(atomic,2):
        result=compare(atomic[left],atomic[right]);atomic_pairs+=1
        if result['review_candidate']:atomic_candidates.append({'left':left,'right':right,**result})
    return {'version':'0.1','records_scope':'five new group profiles and nine atomic passage profiles; old212 via frozen refs',
            'prior_records_and_comparisons':manifest['prior_material_audit'],'records':records,'material_count_total':len(bodies),
            'parent_count_total':len({r['paper_identity'] for r in old_records+records}),'pair_count_total':total,
            'prior_pairs_reused':prior['pair_count_total'],'new_pair_count':len(comparisons),'comparisons':comparisons,
            'exact_repeat_pairs':prior['exact_repeat_pairs']+sum(c['exact_normalized_match'] for c in comparisons),
            'review_candidates':prior['review_candidates']+sum(c['review_candidate'] for c in comparisons),
            'atomic_passages':len(atomic),'atomic_pairs_checked_separate_not_added_to_group_pairs':atomic_pairs,'atomic_candidates':atomic_candidates,
            'catalogue_response_positions':50,'selected_mandatory_positions_with_AorB':40,
            'all_benchmark_deduplication_complete':False,'zero_candidates_not_independent_families':True,'model_called':False}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--output',type=Path);parser.add_argument('--request',type=Path);args=parser.parse_args()
    if args.request:
        _,_,_,layouts=source_views(json.loads(MANIFEST.read_text()));print(json.dumps(check(json.loads(args.request.read_text()),layouts)))
    elif args.output:
        from grade_mode_evidence import REPO
        if (REPO/'build').resolve() not in args.output.resolve().parents:parser.error('Source results must remain ignored build/')
        result=audit();payload=json.dumps(result,ensure_ascii=False,indent=2)+'\n'
        if args.output.exists() and args.output.read_text()!=payload:raise ValueError('Refuse a changed audit overwrite')
        if not args.output.exists():args.output.write_text(payload)
        print(json.dumps({k:result[k] for k in ['material_count_total','parent_count_total','pair_count_total','new_pair_count','review_candidates','atomic_passages','atomic_pairs_checked_separate_not_added_to_group_pairs']}))
    else:parser.error('Choose --request or --output')
