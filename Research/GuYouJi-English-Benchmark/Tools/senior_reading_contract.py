"""Validate complete senior reading sections without reusing junior fixed counts."""
import json
import html
import re
from grade_mode_evidence import load_ref
from check_school_reading_sources import validate as validate_source,digest
from school_reading_contract import ranges


def table_markup(t):
    return '| '+' | '.join(t['headers'])+' |\n| '+ ' | '.join(['---']*3)+' |\n'+'\n'.join('| '+label+' | '+ ' | '.join(str(v)for v in values)+' |'for label,values in zip(t['row_labels'],t['cells']))


def table_option(table,row,col):
    noun=table['materials'][col].lower();article='An'if noun[0] in 'aeiou'else'A'
    return article+' '+noun+' from '+table['row_labels'][row]+'.'


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
        assert bool(section.get('intro'))==bool(label=='A' and (s.get('source_A_intro')or s.get('source_A_program_intro')))
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
    if c['subgroups'][0]['genre']=='four_family_program_profiles':
        assert s['program_profile_entry_spans_bound'] and len(s['source_A_program_entries'])==4
        assert c['response_distribution']==[3,4,4,4] and c['points_each']==2
        assert qs[0]['operation']=='program_booking_detail' and qs[1]['operation']=='target_program_match'
        assert qs[2]['operation']=='cross_program_comparison'
        policy=d['program_policy'];assert policy['all_free'] and policy['all_require_advance_booking']
        assert policy['student_policy_text'] in sections[0]['intro']
        assert len(policy['targeted_age_bands'])==4 and d['program_match']['question_number']==2
        assert policy['targeted_age_bands'][d['program_match']['profile_index']]==d['program_match']['target_age_band']
        assert len(policy['profile_titles'])==len(set(policy['profile_titles']))==4
        assert set(d['program_match']['option_profile_indices'])==set('ABCD')
        for label,index in d['program_match']['option_profile_indices'].items():
            assert index in range(4) and dict(qs[1]['options'])[label]==policy['profile_titles'][index]
        assert qs[1]['answer']==next(label for label,index in d['program_match']['option_profile_indices'].items()if index==d['program_match']['profile_index'])
        for i,u in enumerate(sections[0]['units']):
            assert u.startswith(policy['profile_titles'][i]+'\n') and policy['targeted_age_bands'][i] in u
        assert d['program_match']['target_age_band'] in qs[1]['stem']
        assert policy['monthly_profile_indices']==[2,3]
        assert all('once each month' in sections[0]['units'][i].casefold()for i in policy['monthly_profile_indices'])
        assert qs[9]['operation']=='context_word_meaning'
        assert '**'+d['lexical_target']+'**' in sections[2]['units'][0] and d['lexical_target'] in qs[9]['stem']
        assert qs[12]['operation']=='three_condition_comparison'
        assert len(d['research_conditions'])==3 and len(set(d['research_conditions']))==3
        assert all(v in sections[3]['units'][0]for v in d['research_conditions'])
        assert d['research_scope']['limitations']
    if 'A.credit_requirements' in c['required_lists']:
        from senior_credit_reading_contract import validate as validate_credit
        validate_credit(d,s)
    if 'A.numbered_advice_steps' in c['required_lists']:
        from senior_steps_reading_contract import validate as validate_steps
        validate_steps(d,s)
    if c['subgroups'][0]['genre']=='job_qualification_advertisement_with_subheadings':
        from senior_job_reading_contract import validate as validate_job
        validate_job(d,s)
    if c.get('necessary_images'):
        from senior_graph_reading_contract import validate as validate_graph
        validate_graph(d,s)
    if s.get('native14_author_gate'):
        from senior_care14_reading_contract import validate as validate_care14
        validate_care14(d,s)
    if c['required_tables']:
        assert c['required_tables']==['A.fee_table'] and not c['required_lists']
        table=d['required_table'];assert table['id']=='A.fee_table'
        assert len(table['headers'])==3 and all(x.strip()for x in table['headers'])
        assert len(table['materials'])==len(set(table['materials']))==2
        assert table['headers'][1:]==[m+' (credits)'for m in table['materials']]
        assert len(table['row_labels'])==len(set(table['row_labels']))==3
        assert len(table['cells'])==3 and all(len(row)==2 for row in table['cells'])
        assert all(isinstance(v,int)and v>0 for row in table['cells']for v in row)
        markup=table_markup(table)
        assert sections[0]['units'][0].count(markup)==1
        assert len([line for line in sections[0]['units'][0].splitlines()if line.startswith('|')])==5
        assert all(not re.search(r'^\|',u,re.M)for sec in sections[1:]for u in sec['units'])
        comparison=d['fee_comparison'];assert comparison['question_number']==4
        assert qs[3]['operation']=='table_fee_comparison'
        assert set(comparison['option_cells'])==set('ABCD')
        costs={}
        for label,(row,col)in comparison['option_cells'].items():
            assert row in range(3)and col in range(2)
            costs[label]=table['cells'][row][col]
            assert dict(qs[3]['options'])[label]==table_option(table,row,col)
        best=max(costs.values());assert list(costs.values()).count(best)==1
        assert qs[3]['answer']==next(k for k,v in costs.items()if v==best)
        assert best<max(v for row in table['cells']for v in row)
        assert qs[6]['operation']=='context_phrase_meaning'
        paras=sections[1]['units'][0].split('\n\n');pnum=d['lexical_paragraph']
        assert '**'+d['lexical_target']+'**' in paras[pnum-1]
        assert 'paragraph '+str(pnum) in qs[6]['stem'] and d['lexical_target'] in qs[6]['stem']
        assert qs[13]['operation']=='metaphorical_phrase'
        assert '**'+d['metaphor_target']+'**' in sections[2]['units'][0]
        assert d['metaphor_target'] in qs[13]['stem']
        assert qs[14]['operation']=='closing_quote_purpose'
        assert d['closing_quote'] in sections[2]['units'][0].split('\n\n')[-1]
        assert d['research_scope']['limitations']
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
    return '\n\n'.join(unit_load_text(d,t) for sec in d['sections']for t in ([sec['intro']]if sec.get('intro')else [])+sec['units'])


def unit_load_text(d,text):
    # Opt in for graph manuscripts only; keep all frozen text-only counts intact.
    return re.sub(r'^!\[[^\]]+\]\([^)]+\)\s*$', '', text, flags=re.M) if d.get('source_bound_graph_reading_section') else text


def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());passage=validate(d,b,s)
    assert a['school_complete_senior_reading_section'] and passage==a['student_passage']
    assert a['body_load_text']==body_text(d)
    assert g['questions']==d['questions']
    if d.get('source_bound_graph_reading_section'):
        from senior_graph_reading_contract import check_rendered
        check_rendered(g,a,d)
    else:
        assert not g['requiredPassageImages']
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
    if d.get('credit_notice'):
        from senior_credit_reading_contract import check_rendered
        check_rendered(g,a,d)
    if d.get('source_bound_steps_letter_migration_survey'):
        from senior_steps_reading_contract import check_rendered
        check_rendered(g,a,d)
    if d.get('job_notice'):
        from senior_job_reading_contract import check_rendered
        check_rendered(g,a,d)
    if d.get('source_bound_care_notice14_section'):
        from senior_care14_reading_contract import check_rendered
        check_rendered(g,a,d)
    if d.get('program_policy'):
        assert a['program_policy']==d['program_policy'] and a['program_match']==d['program_match']
        assert a['research_conditions']==d['research_conditions']
    if d.get('required_table'):
        assert a['required_table']==d['required_table'] and a['fee_comparison']==d['fee_comparison']
        rendered=g['passageHtml'];assert rendered.count('<table>')==1
        fragment=rendered.split('<table>')[1].split('</table>')[0]
        rows=[[html.unescape(re.sub('<[^>]+>','',value))for value in re.findall(r'<t[hd]>(.*?)</t[hd]>',row,re.S)]for row in re.findall(r'<tr>(.*?)</tr>',fragment,re.S)]
        t=d['required_table'];assert rows==[t['headers']]+[[label]+[str(v)for v in values]for label,values in zip(t['row_labels'],t['cells'])]
        assert a['load_measure']['table_numeric_cells']==6
    assert a['source_original_key_not_gold']
    return True
