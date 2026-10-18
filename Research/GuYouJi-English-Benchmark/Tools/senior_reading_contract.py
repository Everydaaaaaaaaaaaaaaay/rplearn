"""Validate complete senior reading sections without reusing junior fixed counts."""
import json
import re
from grade_mode_evidence import load_ref
from check_school_reading_sources import validate as validate_source,digest
from school_reading_contract import material,ranges


def validate(d,b,s):
    validate_source(s,b)
    assert b['task_mode']=='school_complete_senior_reading_section'
    assert s['authors_genre_model_ready'] and not s['genre_substructure_further_review_before_authoring']
    c=s['configuration'];n=s['responses']
    assert d['grade']==b['level']==s['level']
    assert d['family']==b['family']==s['kind']=='reading_choice'
    assert d['source_group_id']==s['id']
    assert d['source_binding']==b['id']
    assert d['fictional_people_books_products_studies'] is True
    sections=d['sections'];qs=d['questions']
    assert len(sections)==c['passage_count'] and len(qs)==n
    assert [x['label']for x in sections]==[x['label']for x in c['subgroups']]
    for section,sub,(label,nums) in zip(sections,c['subgroups'],ranges(c)):
        assert section['genre']==sub['genre'] and section['response_numbers']==nums
        assert len(section['units'])==sub['material_units']
        assert all(u.strip()for u in section['units'])
        assert bool(section.get('intro'))==bool(label=='A' and s.get('source_A_intro'))
        for k in nums:
            q=qs[k-1]
            assert q['materialLabel']==label and q['points']==c['points_each']
            assert q['stem'].startswith(label+'组 · ')
    assert [q['number']for q in qs]==list(range(1,n+1))
    for q in qs:
        assert [x[0]for x in q['options']]==list('ABCD')
        assert q['answer'] in 'ABCD' and len(q['answer'])==1
        assert len({x[1].strip().casefold()for x in q['options']})==4
        assert all(x[1].strip()for x in q['options'])
        reasons=dict(x.split('：',1)for x in q['rationale'].split('；'))
        assert set(reasons)==set('ABCD') and all(x.strip()for x in reasons.values())
        assert q['operation']
    assert str(n) in d['instruction'] and str(c['selected_objective_points'])+'分' in d['instruction']
    assert '虚构' in d['instruction'] and '原键非gold' in d['source_notice']
    # These source-specific operations belong to this four-book configuration only.
    if s.get('source_A_book_entries'):
        assert len(sections[0]['units'])==4 and len({u.split('\n')[0]for u in sections[0]['units']})==4
        assert qs[5]['operation']=='context_word_meaning'
        assert '**'+d['lexical_target']+'**' in sections[1]['units'][0]
        assert d['lexical_target'] in qs[5]['stem']
        assert qs[10]['operation']=='whole_material_purpose'
        assert qs[14]['operation']=='application_attitude'
        assert 'limitations' in d['research_scope'] and d['research_scope']['limitations']
    return render(sections,c)


def render(sections,c):
    chunks=[]
    for section,(label,nums) in zip(sections,ranges(c)):
        text='### '+label+'组（第'+str(nums[0])+'—'+str(nums[-1])+'题）\n\n'
        if section.get('intro'):text+=section['intro']+'\n\n'
        text+='\n\n'.join('#### '+label+str(i)+'\n\n'+u for i,u in enumerate(section['units'],1))
        chunks.append(text)
    return '\n\n'.join(chunks)


def body_text(d):
    return '\n\n'.join(t for sec in d['sections']for t in ([sec['intro']]if sec.get('intro')else [])+sec['units'])


def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());passage=validate(d,b,s)
    assert a['school_complete_senior_reading_section'] and passage==a['student_passage']
    assert a['body_load_text']==body_text(d)
    assert g['questions']==d['questions'] and not g['requiredPassageImages']
    assert len(a['question_candidate_audit'])==s['responses']*4
    for q in d['questions']:
        rows=[x for x in a['question_candidate_audit']if x['number']==q['number']]
        reasons=dict(x.split('：',1)for x in q['rationale'].split('；'))
        assert [x['label']for x in rows]==list('ABCD')
        for row,(label,text) in zip(rows,q['options']):
            assert row['text']==text and row['reason']==reasons[label]
            assert row['is_best']==(label==q['answer']) and row['material_label']==q['materialLabel']
    for label,nums in ranges(s['configuration']):
        assert label+'组（第'+str(nums[0])+'—'+str(nums[-1])+'题）' in g['passageHtml']
    assert a['source_original_key_not_gold']
    return True
