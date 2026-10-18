#!/usr/bin/env python3
"""Exercise complete school-cloze source binding and truncated/ambiguous data guards."""
import argparse
import copy
import json
from pathlib import Path
from check_all_levels_review import extract
from grade_mode_evidence import load_ref
from review_run_plan import resolve_plan
from school_cloze_contract import check, validate, source_option_rows


def run(page):
    assert source_option_rows('44.A.complained B. declared C. suggested D. wondered') == [(44,list('ABCD'))]
    assert source_option_rows('44. A. complained B. declared C. suggested D. wondered') == [(44,list('ABCD'))]
    assert source_option_rows('44 A. complained B. declared C. suggested D. wondered') == [(44,list('ABCD'))]
    assert source_option_rows('44.A.complained B. declared B. suggested D. wondered') == [(44,list('ABBD'))]
    data = extract(page)
    _,plan = resolve_plan(data['active_run_plan'])
    idx = json.loads(load_ref(plan['current_gap_completion']).read_text())
    results = []
    for meta in idx['candidates']:
        audit = json.loads(load_ref(meta['author_check']).read_text())
        if not audit.get('school_complete_cloze'):
            continue
        group = data['groups'][meta['id']]
        binding = next(b for b in json.loads(load_ref(audit['source_bindings']).read_text())['bindings'] if b['id']==audit['source_binding'])
        source = next(s for s in json.loads(load_ref(binding['source_index']).read_text())['groups'] if s['id']==binding['source_group_id'])
        check(group,audit,binding,source)
        draft = json.loads(load_ref(audit['manuscript']).read_text())
        cases = {}
        cases['fixed_six_truncation'] = lambda d: d['questions'].__delitem__(slice(6,None))
        cases['duplicate_option_label'] = lambda d: d['questions'][0]['options'].__setitem__(1,list(d['questions'][0]['options'][0]))
        cases['duplicate_option_text'] = lambda d: d['questions'][0]['options'][1].__setitem__(1,d['questions'][0]['options'][0][1])
        cases['missing_candidate_reason'] = lambda d: d['questions'][0].__setitem__('rationale',d['questions'][0]['rationale'].split('；')[0])
        cases['substring_key_AB'] = lambda d: d['questions'][0].__setitem__('answer','AB')
        cases['empty_key'] = lambda d: d['questions'][0].__setitem__('answer','')
        cases['missing_whole_material'] = lambda d: d['sections'].__delitem__(slice(0,None))
        cases['missing_gap'] = lambda d: d['sections'][0].__setitem__('passage',d['sections'][0]['passage'].replace('(1) ____','word'))
        cases['duplicate_gap'] = lambda d: d['sections'][0].__setitem__('passage',d['sections'][0]['passage'].replace('(2) ____','(1) ____'))
        cases['wrong_source_anchor'] = lambda d: d.__setitem__('source_group_id','different-count-source')
        cases['wrong_grade'] = lambda d: d.__setitem__('grade',12 if d['grade']!=12 else 11)
        cases['extra_material_not_bound'] = lambda d: d['sections'].append(copy.deepcopy(d['sections'][0]))
        if len(draft['sections'])>1:
            cases.update({
                'only_A_material':lambda d:d['sections'].__delitem__(slice(1,None)),
                'swap_passage_bodies':lambda d:[d['sections'][i].__setitem__('passage',draft['sections'][1-i]['passage'])for i in range(2)],
                'wrong_material_label':lambda d:d['sections'][1].__setitem__('label','A'),
                'wrong_section_range':lambda d:d['sections'][1].__setitem__('response_numbers',list(range(1,len(d['sections'][1]['response_numbers'])+1))),
                'wrong_response_material':lambda d:d['questions'][-1].__setitem__('materialLabel','A'),
                'wrong_response_stem':lambda d:d['questions'][-1].__setitem__('stem','A篇 · 第'+str(len(d['questions']))+'空'),
                'wrong_response_points':lambda d:d['questions'][0].__setitem__('points',99),
            })
        rejected=[]
        for name,mutate in cases.items():
            bad=copy.deepcopy(draft);mutate(bad)
            try:validate(bad,binding,source)
            except (AssertionError,ValueError,KeyError):rejected.append(name)
            else:raise AssertionError('Invalid complete group accepted: '+name)
        source_cases={
            'false_full_input':lambda s:s.__setitem__('source_full_inputs_verified',False),
            'source_promoted_to_gold':lambda s:s.__setitem__('source_key_is_gold',True),
            'source_span_changed':lambda s:s['source_spans'][0].__setitem__('sha256','0'*64),
            'cartesian_option_count':lambda s:s.__setitem__('options_each',3 if s['options_each']==4 else 4),
        }
        if source.get('source_pdf'):
            source_cases.update({
                'visual_verification_false':lambda s:s.__setitem__('image_all_body_and_all_candidate_rows_visually_verified',False),
                'source_page_images_missing':lambda s:s.__setitem__('source_input_images',[]),
                'source_image_sha_changed':lambda s:s['source_input_images'][0].__setitem__('sha256','0'*64),
            })
        if len(draft['sections'])>1:
            source_cases.update({
                'unrelated_parent':lambda s:s['source_observations'][1].__setitem__('paper_id','different-parent'),
                'whole_header_digest_changed':lambda s:s['whole_section'].__setitem__('sha256','0'*64),
                'wrong_whole_score':lambda s:s['configuration'].__setitem__('section_points',99),
                'one_member_reused':lambda s:s['source_member_ids'].__setitem__(1,s['source_member_ids'][0]),
                'second_source_span_missing':lambda s:s['source_spans'].__delitem__(slice(1,None)),
                'optional_A_or_B_invented':lambda s:s['whole_section'].__setitem__('mandatory_all_materials',False),
                'second_member_input_missing':lambda s:s['source_observations'][1].__setitem__('necessary_input_complete',False),
                'invented_different_subgroup_points':lambda s:s['configuration'].__setitem__('points_each_subgroup',[1.5,.5]),
            })
        for name,mutate in source_cases.items():
            bad=copy.deepcopy(source);mutate(bad)
            # Rehash the altered record so these exercise the policy/span guard,
            # rather than merely failing the record-identity guard.
            from school_cloze_contract import digest
            bb=copy.deepcopy(binding);bb['source_record_sha256']=digest(json.dumps(bad,sort_keys=True,ensure_ascii=False))
            try:validate(draft,bb,bad)
            except (AssertionError,ValueError,KeyError):rejected.append(name)
            else:raise AssertionError('Invalid source accepted: '+name)
        results.append(dict(id=meta['id'],responses=len(group['questions']),full_group_candidate_substitutions=len(audit['choice_pair_audit']),negative_controls=rejected,positive_whole_contract=True))
    assert results
    return dict(records=results,complete_groups=len(results),negative_controls=sum(len(r['negative_controls'])for r in results),full_candidate_substitutions=sum(r['full_group_candidate_substitutions']for r in results),not_independent_semantic_validation=True)


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--page',type=Path,default=Path('build/english-benchmark-quality-review/index.html'));p.add_argument('--report',type=Path,required=True);a=p.parse_args();result=run(a.page)
    if a.report.exists():raise ValueError('Do not overwrite frozen reports')
    a.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result))
