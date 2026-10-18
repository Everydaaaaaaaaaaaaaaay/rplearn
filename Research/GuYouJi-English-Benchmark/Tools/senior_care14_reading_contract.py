"""Grade10 complete fourteen-response notice/narrative/report/research section.

Input/author consistency checks do not independently prove answer quality,
reading difficulty, factual truth, rights or production marking.
"""
import re

OPERATIONS=['notice_recruitment_purpose','notice_primary_concern','preferred_experience_with_essentials_assumed',
 'narrative_initial_distraction','narrative_personal_concern','narrative_resolution','narrative_main_implication',
 'context_phrase_meaning','example_function','project_report_purpose',
 'intro_technology_change','spelling_writing_relationship','context_metaphorical_phrase','whole_research_conclusion']
HEADINGS=['Position','Place','Hours','Role','Skills and Experience Required']


def notice(j):
    fields=[j['role']+' (No pay; free meals during each duty period).',j['place'],
            'Part time. '+j['schedule'],
            j['duties']+' '+j['primary_concern'],
            'Applicants must be honest and patient, listen carefully, hold a current driving licence, and communicate fluently in both written and spoken English. '+
            j['required_context']+' '+j['preferred_sentence']]
    return j['organisation']+'\n\n'+j['intro']+'\n\n'+'\n\n'.join('#### '+h+'\n\n'+v for h,v in zip(HEADINGS,fields))


def validate(d,s):
    assert s['native14_author_gate']=='grade10_care_notice14_v1' and s['level']==10
    c=s['configuration'];assert c['response_distribution']==[3,4,3,4]
    assert c['responses']==14 and c['points_each']==2 and c['selected_objective_points']==28
    assert not c['required_images'] and not c['illustrative_images'] and not c['required_lists']
    assert d['source_bound_care_notice14_section']
    assert [q['operation']for q in d['questions']]==OPERATIONS
    qs=d['questions'];j=d['care_notice']
    assert j['paid'] is False and j['meals_included'] is True and j['part_time'] is True
    assert j['place'].strip() and j['schedule'].strip() and j['role'].strip()
    assert j['primary_concern'] and j['preferred_sentence'] and j['required_context']
    assert d['sections'][0]['units']==[notice(j)]
    assert re.findall(r'(?m)^#### (.+)$',d['sections'][0]['units'][0])==HEADINGS
    assert d['all_applicants_essential_requirements_and_availability_assumed_met']
    assert 'essential requirements' in qs[2]['stem'] and 'availability' in qs[2]['stem']
    cases=d['experience_options'];assert set(cases)==set('ABCD')
    assert [label for label,c in cases.items()if c['has_explicit_preferred_experience']]==[qs[2]['answer']]
    for label,case in cases.items():assert dict(qs[2]['options'])[label]==case['text']
    assert d['preferred_experience_evidence']==j['preferred_sentence']
    assert d['narrative_is_not_real_emergency_advice']
    B=d['sections'][1]['units'][0]
    for key in ['distraction','personal_concern','first_attempt_limit','remembered_advice','resolution','ending']:
        assert len(d['narrative_evidence'][key])>20 and d['narrative_evidence'][key] in B
    C=d['sections'][2]['units'][0];paras=C.split('\n\n');target=d['C_lexical_target']
    assert '**'+target+'**' in paras[0] and target in qs[7]['stem'] and 'paragraph 1' in qs[7]['stem']
    assert d['C_example'] in C and d['C_purpose'] in C
    assert d['C_no_income_or_need_inferred_from_appearance']
    D=d['sections'][3]['units'][0];paras=D.split('\n\n')
    assert len(paras)==6 and d['D_first_study'] in paras[2] and d['D_second_study'] in paras[3]
    assert '**'+d['D_lexical_target']+'**' in paras[4]
    assert d['D_lexical_target'] in qs[12]['stem'] and 'paragraph 5' in qs[12]['stem']
    assert d['D_word_form_to_expression_evidence'] in paras[4]
    assert d['D_checker_limit_evidence'] in paras[5]
    assert d['fictional_studies_not_measured_educational_efficacy']
    assert d['D_direction']=='ideas_to_word_forms_to_written_symbols'
    assert len(d['answer_evidence'])==14
    for q,e in zip(qs,d['answer_evidence']):
        assert e['number']==q['number'] and e['best_text']==dict(q['options'])[q['answer']]
        body=d['sections']['ABCD'.index(q['materialLabel'])]['units'][0]
        assert len(e['evidence'])>20 and e['evidence'] in body
    return True


def check_rendered(g,a,d):
    assert a['source_bound_care_notice14_section'] and not g['requiredPassageImages']
    for key in ['care_notice','experience_options','narrative_evidence','answer_evidence']:
        assert a[key]==d[key]
    assert all(h in g['passageHtml']for h in HEADINGS)
    assert a['load_measure']['notice_required_fields']==5
    assert a['load_measure']['research_accounts']==2
    assert a['load_measure']['output_requirement_Han_characters']>0
    assert a['load_measure']['stem_Han_characters']==14
    return True
