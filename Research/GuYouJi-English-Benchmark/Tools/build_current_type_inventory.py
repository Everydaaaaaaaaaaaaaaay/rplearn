#!/usr/bin/env python3
"""Reconcile the current preview with authority references and unresolved source cells.

This is a count/configuration inventory, not a claim that the taxonomy is exhaustive.
No source assets are copied or reacquired.
"""
import argparse
import hashlib
import json
from pathlib import Path
from check_all_levels_review import extract, group_sha
from grade_mode_evidence import BASE, REPO, load_ref
from review_run_plan import resolve_plan


def ref(p):
    return {'path':str(p.relative_to(BASE)) if p.is_relative_to(BASE) else str(p.relative_to(REPO)),
            'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}


def build(page,version="0.1"):
    data=extract(page)
    _,plan=resolve_plan(data['active_run_plan'])
    atlas=json.loads(load_ref(plan['current_authority_atlas']).read_text())
    appearance=BASE/'FirstRelease/Sampling/grade-task-appearance-v0.1.json'
    observed=json.loads(appearance.read_text())
    by_level={str(i['level']):i for i in atlas['levels']}
    aliases={str(i):'junior'+str(i-6) if i<10 else 'senior'+str(i-9) for i in range(7,13)}
    rows=[]
    for level in data['grades']:
        authority=by_level[aliases.get(str(level),str(level))]
        cells=[c for c in data['cells']if c['grade']==level and c['observed']]
        current=[];unfilled=[]
        for cell in cells:
            ids=cell.get('groupIds') or ([cell['groupId']]if cell.get('groupId')else [])
            inherited=next((r for r in observed['cells']if r['grade']==level and r['family']==cell['family']),{})
            if not ids:
                unfilled.append(dict(family=cell['family'],label=cell['label'],state=cell['state'],
                    old_author_reason=cell.get('pauseReason'),source_group_ids=inherited.get('source_group_ids',cell.get('source_group_ids',[])),
                    whole_family_excluded=False,action='review_specific_source_constraint_and_reauthor_complete_group;do_not_unhold_old_payload_or_assume_all_modes_open'))
                continue
            groups=[data['groups'][i]for i in ids]
            current.append(dict(family=cell['family'],label=cell['label'],complete_groups=len(groups),responses=sum(len(g['questions'])for g in groups),
                group_ids=ids,source_group_ids=sorted({a for g in groups for a in g['anchor_group_ids']}),
                configurations=[dict(id=g['id'],payload_sha256=group_sha(g),responses=len(g['questions']),options_per_response=[len(q['options'])for q in g['questions']],
                    format_summary=g.get('formatSummary'),instruction=g.get('instruction'),fixed_shared_bank=g.get('fixedSharedBank',False),
                    word_limits=[{'number':q['number'],'normalization':q['fillMarking'].get('normalization'),'whole_count':q['fillMarking'].get('wholeCount'),'unknown_syntax':q['fillMarking'].get('unknownSyntax'),'given_lemma':q.get('givenLemma'),'min_words':q['fillMarking'].get('minWords'),'max_words':q['fillMarking'].get('maxWords'),'required_keyword':q['fillMarking'].get('requiredWord'),'required_initial':q['fillMarking'].get('requiredInitial'),'bank_entry':q.get('bankEntry'),'bank_reuse_rule':q.get('bankReuse')}
                                 for q in g['questions']if q.get('fillMarking')],
                    audio_tracks=len(g.get('requiredAudioAssets',[])),required_images=len(g.get('requiredPassageImages',[]))+len(g.get('requiredImageAssets',[])),
                    candidate=g['candidate'],author_check=g['author_check'])for g in groups],
                author_configurations_not_independent_source_count=True,three_drafts_not_type_completeness=True))
        issues=[dict(id=i['id'],label=i['label'],state=i['state_label'],detail=i['detail'],evidence=i['evidence'])for i in data['coverage_audit']['issues']if level in i['levels'] or aliases.get(str(level)) in i['levels']]
        rows.append(dict(level=level,label=data['levelLabels'][str(level)],authority_ids=authority['authority_ids'],historical_atlas_summary=authority['requirements_summary'],
            authority_reference_findings=[{'id':v['id'],'role':v['role'],'finding':v['finding']}for v in atlas['authorities']if v['id']in authority['authority_ids']],
            current_types=current,observed_source_cells_without_current_author=unfilled,open_audit_issues=issues,
            complete_groups=sum(r['complete_groups']for r in current),responses=sum(r['responses']for r in current),
            current_type_count=len(current),old_atlas_counts_replaced_by_this_snapshot=True,exhaustive_type_catalogue_proven=False))
    assert sum(r['complete_groups']for r in rows)==len(data['groups'])
    assert sum(r['responses']for r in rows)==sum(len(g['questions'])for g in data['groups'].values())
    assert sum(r['current_type_count']for r in rows)==data['source_form_representative_cells']
    # Persist the actual labels too; families in old imports may have different
    # internal spellings, which must not silently turn into a missing form.
    required={
        'undergraduate':{'reading_choice','shared_bank','paragraph_matching','listening_news_choice','listening_long_conversation_choice','listening_passage_choice'},
        'postgraduate':{'reading_choice','shared_bank','paragraph_matching','listening_long_conversation_choice','listening_passage_choice','listening_lecture_choice'},
        'advanced':{'choice_cloze','open_cloze','passage_form','keyword_transformation','reading_choice','cross_text_matching','paragraph_gap_insertion','multiple_text_information_matching','listening_extract_choice','listening_sentence_completion','listening_interview_choice','listening_double_matching'}}
    adult=[]
    for level in ['undergraduate','postgraduate','advanced']:
        r=next(r for r in rows if r['level']==level)
        adult.append(dict(level=level,displayed_families=[c['family']for c in r['current_types']],
            authoritative_type_count=12 if level=='advanced'else 6,
            boundary='C1reference8reading_use+4listening;notproductadvanced_equivalence'if level=='advanced'else'CETspecificblueprint;notdegreepopulation',
            known_missing=sorted(required[level]-{c['family']for c in r['current_types']}),
            school_writing_and_translation_excluded=True))
    return dict(version=version,scope='15levels_current_source_author_configuration_inventory',current_plan=ref(load_ref(data['active_run_plan']) if isinstance(data['active_run_plan'],dict) else BASE/data['active_run_plan']),
        authority_atlas=plan['current_authority_atlas'],middle_appearance=ref(appearance),
        groups=len(data['groups']),responses=sum(len(g['questions'])for g in data['groups'].values()),display_cells=data['source_form_representative_cells'],
        levels=rows,adult_blueprint_comparison=adult,
        observed_source_cells_without_author=sum(len(r['observed_source_cells_without_current_author'])for r in rows),
        additional_media_and_current_nonpaper_gaps_retained=True,unknown_cartesian_product_not_required=True,
        original_paused_groups=data['paused_concrete_groups'],
        pending_specific_modes=data.get('pending_specific_modes',[]),unfilled_specific_modes=data.get('unfilled_specific_modes',0),
        full_source_and_author_count_separate=True,all_required_types_complete=False,independent_teacher_student_commercial_production=False)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--page',type=Path,default=REPO/'build/english-benchmark-quality-review/index.html');p.add_argument('--output',type=Path,required=True);p.add_argument('--version',default='0.1');a=p.parse_args();result=build(a.page,a.version)
    if a.output.exists():raise ValueError('Frozen inventories must not be overwritten')
    a.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:result[k]for k in ['groups','responses','display_cells','observed_source_cells_without_author','all_required_types_complete']}))
