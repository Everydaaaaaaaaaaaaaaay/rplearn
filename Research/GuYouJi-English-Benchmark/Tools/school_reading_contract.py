"""Keep all subgroups and text units of an observed objective reading section."""
import hashlib
import json
import re
from grade_mode_evidence import load_ref


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def ranges(config):
    cursor=1;result=[]
    for subgroup in config['subgroups']:
        nums=list(range(cursor,cursor+subgroup['responses']))
        result.append((subgroup['label'],nums));cursor+=len(nums)
    return result


def material(sections,config):
    return '\n\n'.join('### '+label+'组（第'+str(nums[0])+'—'+str(nums[-1])+'题）\n\n'+
        '\n\n'.join('#### '+label+str(i)+'\n\n'+unit for i,unit in enumerate(section['units'],1))
        for section,(label,nums) in zip(sections,ranges(config)))


def validate(draft,binding,source):
    assert draft['grade']==binding['level']==source['level']
    assert draft['family']==binding['family']==source['kind']=='reading_choice'
    assert draft['source_group_id']==binding['source_group_id']==source['id']
    assert binding['source_record_sha256']==digest(json.dumps(source,sort_keys=True,ensure_ascii=False))
    assert source['source_full_inputs_verified'] and not source['source_key_is_gold']
    assert source['source_count_increment']==binding['new_source_count']==0
    cfg=source['configuration'];assert cfg['all_selected_subgroups_mandatory']
    assert source['responses']==binding['responses']==sum(cfg['response_distribution'])==17
    assert source['options_each']==binding['options_each']==4
    assert cfg['subgroup_count']==len(cfg['subgroups'])==len(draft['sections'])==5
    assert cfg['response_distribution']==[s['responses']for s in cfg['subgroups']]
    assert cfg['materials']==sum(s['material_units']for s in cfg['subgroups'])==9
    assert cfg['points_each']==2 and cfg['selected_objective_points']==34
    assert cfg['whole_reading_points']==40 and cfg['whole_reading_responses']==20
    assert len(cfg['excluded_open_response_numbers'])==3
    assert (source['responses']+len(cfg['excluded_open_response_numbers']))*cfg['points_each']==cfg['whole_reading_points']
    assert not cfg['shared_candidates'] and not cfg['necessary_audio'] and not cfg['necessary_images']
    header=source['whole_objective_header'];raw=load_ref(header['source']).read_text()
    text=raw[header['start_offset']:header['end_offset']]
    assert header['text']==text and digest(text)==header['sha256']
    assert '共20小题' in text and '每小题2分' in text and '满分40分' in text
    assert '第一节 阅读下列短文' in text
    assert raw.count(header['exclusion_boundary'])==1 and '第二节' in header['exclusion_boundary']
    assert len(source['source_spans'])==len(source['source_observations'])==5
    previous_end=header['end_offset'];all_source_numbers=[]
    for span,ob,subgroup in zip(source['source_spans'],source['source_observations'],cfg['subgroups']):
        assert span['source']==header['source']==ob['source_text_ref']
        assert span['start_offset']>=previous_end;previous_end=span['end_offset']
        assert not raw[header['end_offset']:source['source_spans'][0]['start_offset']].strip()
        selected=raw[span['start_offset']:span['end_offset']]
        assert digest(selected)==span['sha256'] and selected.startswith(subgroup['label']+'\n')
        assert span['label']==subgroup['label']
        assert span['source_member_id']==ob['id']
        assert ob['paper_id']==source['source_observations'][0]['paper_id']
        assert ob['necessary_input_complete'] is True and ob['shape']['family']=='reading_choice'
        assert ob['shape']['grade']==source['level'] and ob['shape']['options_each']==4
        assert ob['shape']['responses']==subgroup['responses']==len(span['question_numbers'])
        assert span['material_unit_count']==subgroup['material_units']
        qstart=re.search(r'(?m)^'+str(span['question_numbers'][0])+r'\.',selected).start()
        body=selected[2:qstart].strip()
        if span['label'] in ['A','B']:
            assert len([line for line in body.splitlines()if line.strip()])==span['material_unit_count']
        else:
            assert span['material_unit_count']==1
        qtext=selected[qstart:]
        qs=list(re.finditer(r'(?m)^(\d+)\.(.*?)(?=^\d+\.|\Z)',qtext,re.S))
        assert [int(q[1])for q in qs]==span['question_numbers']
        assert all(re.findall(r'(?:^|\s)([A-D])\.',q[2])==list('ABCD')for q in qs)
        all_source_numbers+=span['question_numbers']
    assert all_source_numbers==list(range(56,73))
    assert max(all_source_numbers)<min(cfg['excluded_open_response_numbers'])
    sections=draft['sections'];qs=draft['questions']
    assert [s['label']for s in sections]==[s['label']for s in cfg['subgroups']]
    for section,subgroup,(label,numbers) in zip(sections,cfg['subgroups'],ranges(cfg)):
        assert section['genre']==subgroup['genre'] and section['response_numbers']==numbers
        assert len(section['units'])==subgroup['material_units']
        assert all(u.strip() and not re.search(r'^#{1,4}\s',u,re.M)for u in section['units'])
        for n in numbers:
            q=qs[n-1];assert q['materialLabel']==label and q['points']==cfg['points_each']
            assert q['stem'].startswith(label+'组 · ')
    assert [q['number']for q in qs]==list(range(1,18))
    for q in qs:
        assert [x[0]for x in q['options']]==list('ABCD')
        assert q['answer'] in 'ABCD' and len(q['answer'])==1
        assert len({x[1].strip().casefold()for x in q['options']})==4
        assert all(x[1].strip()for x in q['options'])
        reasons=dict(x.split('：',1)for x in q['rationale'].split('；'))
        assert set(reasons)==set('ABCD') and all(reasons.values())
    assert sections[0]['units'][0].count('**it**')==1
    assert '“it”' in qs[0]['stem'] and qs[0]['operation']=='reference_word'
    assert sections[2]['units'][0].count('**'+draft['lexical_target']+'**')==1
    assert draft['lexical_target'] in qs[10]['stem'] and qs[10]['operation']=='context_word_meaning'
    assert qs[15]['operation']=='contradicted_statement' and 'NOT true' in qs[15]['stem']
    assert qs[16]['operation']=='whole_material_title'
    assert '第17' in draft['instruction'] and '34分' in draft['instruction']
    assert '第二节' in draft['source_notice'] and '开放' in draft['source_notice']
    return material(sections,cfg)


def check(group,audit,binding,source):
    draft=json.loads(load_ref(audit['manuscript']).read_text())
    passage=validate(draft,binding,source)
    assert audit['school_complete_reading_section'] and audit['student_passage']==passage
    assert audit['body_load_text']=='\n\n'.join(u for s in draft['sections']for u in s['units'])
    assert group['questions']==draft['questions'] and not group['requiredPassageImages']
    assert len(audit['question_candidate_audit'])==68
    for q in draft['questions']:
        rows=[r for r in audit['question_candidate_audit']if r['number']==q['number']]
        assert [r['label']for r in rows]==list('ABCD')
        reasons=dict(x.split('：',1)for x in q['rationale'].split('；'))
        for row,(label,text) in zip(rows,q['options']):
            assert row['text']==text and row['reason']==reasons[label]
            assert row['is_best']==(label==q['answer'])
            assert row['material_label']==q['materialLabel']
    for label,numbers in ranges(source['configuration']):
        assert label+'组（第'+str(numbers[0])+'—'+str(numbers[-1])+'题）' in group['passageHtml']
    assert audit['negative_question16_key_explicitly_contradicted_not_merely_unstated']
    assert audit['source_original_key_not_gold']
    return True
