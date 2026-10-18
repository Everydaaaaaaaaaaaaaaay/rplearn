"""Bind a complete school cloze configuration; counts alone are not difficulty proof."""
import hashlib
import json
import re
import base64
import xml.etree.ElementTree as ET
from grade_mode_evidence import load_ref


def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()


def source_option_rows(selected):
    # Some preserved public texts print 44.A.complained, without spaces.
    # Accept that layout while retaining literal numbering and all option labels.
    result=[]
    for match in re.finditer(r'(?m)^(\d+)\.?\s*A\..*$',selected):
        row=re.sub(r'^\d+\.?\s*','',match[0])
        result.append((int(match[1]),re.findall(r'(?:^|\s)([A-D])\.',row)))
    return result


def section_ranges(sections):
    cursor=1;result=[]
    for section in sections:
        numbers=list(range(cursor,cursor+len(re.findall(r'\((\d+)\) ____',section['passage']))))
        result.append((section['label'],numbers));cursor+=len(numbers)
    return result


def student_material(sections):
    if len(sections)==1:return sections[0]['passage']
    return '\n\n'.join('### '+label+'篇（第'+str(numbers[0])+'—'+str(numbers[-1])+'空）\n\n'+section['passage'] for section,(label,numbers) in zip(sections,section_ranges(sections)))


def without_gloss_figures(passage):
    return re.sub(r'^!\[[^\]]+\]\([^)]+\)\s*$', '', passage, flags=re.M)


def validate_gloss_figures(draft, source, passage):
    expected=source['configuration'].get('inline_illustrated_glosses',0)
    if not expected:
        assert not draft.get('gloss_figures')
        return
    figures=draft['gloss_figures'];assert len(figures)==expected==2
    assert source['configuration']['necessary_images']
    assert len(source['source_illustrated_glosses'])==expected
    score=source['source_scoring_evidence'];config=source['configuration']
    raw=load_ref(source['source_spans'][0]['source']).read_text()
    assert score['header'] in raw
    item_points=float(re.search(r'每小题\s*([0-9.]+)\s*分',score['header'])[1])
    whole_points=float(re.search(r'共\s*([0-9.]+)\s*分',score['header'])[1])
    assert config['selected_subgroup_not_entire_mixed_section']
    assert config['points_each_subgroup']==[item_points]
    assert score['selected_points']==config['section_points']==len(score['selected_numbers'])*item_points
    assert score['selected_numbers']==source['source_spans'][0]['question_numbers']
    assert set(score['selected_numbers']).isdisjoint(score['other_subgroup_numbers'])
    assert score['whole_section_points']==config['original_mixed_section_points']==whole_points
    assert whole_points==(len(score['selected_numbers'])+len(score['other_subgroup_numbers']))*item_points
    embeds=list(re.finditer(r'^!\[([^\]]+)\]\(([^)]+)\)\s*$',passage,re.M))
    assert len(embeds)==len(figures) and len({f['asset']['path']for f in figures})==len(figures)
    for figure,embed in zip(figures,embeds):
        assert figure['role']=='illustrated_word_gloss_not_answer_hint'
        assert embed[1]==figure['alt'] and embed[2]==figure['asset']['path']
        assert figure['term'] in figure['alt'] and figure['term'] in figure['anchor_text']
        before=passage[:embed.start()].rstrip()
        assert before.endswith(figure['anchor_text'])
        assert before.count(figure['anchor_text'])==1
        assert figure['anchor_text'].count(figure['term'])==1
        raw=load_ref(figure['asset']).read_bytes();svg=ET.fromstring(raw)
        assert svg.tag=='{http://www.w3.org/2000/svg}svg'
        assert svg.attrib['width']=='160' and svg.attrib['height']=='140'
        assert svg.attrib['viewBox']=='0 0 160 140'
        assert svg.attrib['role']=='img' and svg.attrib['aria-label']==figure['alt']
        assert [e.text for e in svg.iter('{http://www.w3.org/2000/svg}text')]==[figure['term']]
        assert not list(svg.iter('{http://www.w3.org/2000/svg}image'))
        assert not list(svg.iter('{http://www.w3.org/2000/svg}script'))


def validate_whole_section(source):
    config=source['configuration'];whole=source['whole_section'];count=source['responses']
    assert whole['mandatory_all_materials'] and len(set(whole['member_ids']))==config['materials']
    assert whole['member_ids']==source['source_member_ids']
    raw=load_ref(whole['source']).read_text();header=raw[whole['start_offset']:whole['end_offset']]
    assert digest(header)==whole['sha256'] and '任选' not in header
    number_match=re.search(r'共\s*(\d+)\s*小题',header);assert number_match
    assert int(number_match[1])==count
    score_match=re.search(r'(?:满分|计)\s*([0-9]+(?:\.[0-9]+)?)\s*分',header);assert score_match
    total=float(score_match[1])
    points=config['points_each_subgroup'];assert len(points)==config['materials']
    assert all(type(p) in [int,float] and p>0 for p in points)
    assert sum(p*s['responses'] for p,s in zip(points,config['subgroups']))==total==config['section_points']
    if len(set(points))==1:
        point_match=re.search(r'每小题\s*([0-9]+(?:\.[0-9]+)?)\s*分',header);assert point_match
        assert float(point_match[1])==points[0]
    else:
        for subgroup,p in zip(config['subgroups'],points):
            point_match=re.search(re.escape(subgroup['label'])+r'篇每小题\s*([0-9]+(?:\.[0-9]+)?)\s*分',header);assert point_match
            assert float(point_match[1])==p
    assert len(source['source_spans'])==len(source['source_observations'])==config['materials']
    previous_end=whole['end_offset']
    for index,(member,span,obs,subgroup) in enumerate(zip(whole['member_ids'],source['source_spans'],source['source_observations'],config['subgroups'])):
        assert previous_end<=span['start_offset']<span['end_offset']
        if index==0:
            assert raw[previous_end:span['start_offset']].strip()==span['label']
        else:
            marker=raw.rfind('\n'+span['label']+'\n',previous_end,span['start_offset'])
            assert marker>=previous_end and not raw[marker+3:span['start_offset']].strip()
        previous_end=span['end_offset']
        assert member==span['source_member_id']==obs['id']
        assert span['label']==subgroup['label']==obs['shape']['details']['part']
        assert obs['paper_id']==source['paper_id']
        assert span['source']==obs['source_text_ref']==whole['source']
        assert obs['shape']['grade']==source['level'] and obs['shape']['family']=='choice_cloze'
        assert obs['shape']['responses']==len(span['question_numbers'])==subgroup['responses']
        assert obs['shape']['options_each']==source['options_each']
        assert obs['shape']['details']['section_materials']==config['materials']
        assert obs['shape']['details']['section_subgroup_slots']==[s['responses'] for s in config['subgroups']]
        assert obs['necessary_input_complete'] is True
        if 'points_each' in obs['shape']['details']:
            assert obs['shape']['details']['points_each']==points[index]


def validate(draft, binding, source):
    assert draft['grade'] == binding['level'] == source['level']
    assert draft['family'] == binding['family'] == source['kind'] == 'choice_cloze'
    assert draft['source_group_id'] == binding['source_group_id'] == source['id']
    assert binding['source_record_sha256'] == digest(json.dumps(source, sort_keys=True, ensure_ascii=False))
    assert source['source_full_inputs_verified'] and not source['source_key_is_gold']
    if source.get('source_pdf'):
        load_ref(source['source_pdf'])
        assert source['image_all_body_and_all_candidate_rows_visually_verified']
        assert source['source_input_images']
        for image_ref in source['source_input_images']:load_ref(image_ref)
    assert source['source_count_increment'] == 0 and binding['new_source_count'] == 0
    if source.get('scoring_observation'):
        observation=source['scoring_observation'];raw=load_ref(observation['source']).read_text()
        header=raw[observation['start_offset']:observation['end_offset']]
        assert digest(header)==observation['sha256'] and header==observation['text']
        assert header=='二、完形填空（共10小题，计10分）'
        assert observation['item_points'] is None and observation['section_points']==10
        assert source['source_item_points_explicit'] is False
        assert source['configuration']['point_allocation_basis']=='author_uniform_from_observed_total_not_itemwise_printed'
        assert source['configuration']['points_each_subgroup']==[1]
        assert '未逐题印分值' in draft['source_notice'] and '本稿按每题1分' in draft['source_notice']
    count = source['responses']; options = source['options_each']
    assert binding['responses'] == count and binding['options_each'] == options
    config = source['configuration']; sections = draft['sections']
    assert config['materials'] == len(sections) == len(config['subgroups'])
    assert sum(p['responses'] for p in config['subgroups']) == count
    assert config['each_gap_independent'] and not config['shared_bank']
    assert [len(re.findall(r'\((\d+)\) ____',s['passage'])) for s in sections] == [p['responses'] for p in config['subgroups']]
    assert [s['label'] for s in sections] == [p['label'] for p in config['subgroups']]
    for span in source['source_spans']:
        raw = load_ref(span['source']).read_text()
        selected = raw[span['start_offset']:span['end_offset']]
        assert digest(selected) == span['sha256']
        rows = source_option_rows(selected)
        assert [number for number,labels in rows] == span['question_numbers']
        assert all(labels == list('ABCD'[:options]) for number,labels in rows)
        assert span['instruction'] in raw and span['instruction_sha256'] == digest(span['instruction'])
    qs = draft['questions']; assert len(qs) == count
    assert [q['number'] for q in qs] == list(range(1,count+1))
    if config['materials']>1:
        validate_whole_section(source)
        for section,(label,numbers) in zip(sections,section_ranges(sections)):
            assert section['response_numbers']==numbers
        for (label,numbers),points in zip(section_ranges(sections),config['points_each_subgroup']):
            for number in numbers:
                q=draft['questions'][number-1]
                assert q['materialLabel']==label and q['points']==points
                expected_stem=label+'篇 · 第'+str(number)+'空'
                if len(set(config['points_each_subgroup']))>1:expected_stem+='（'+str(points)+'分）'
                assert q['stem']==expected_stem
    passage = student_material(sections)
    validate_gloss_figures(draft,source,passage)
    assert re.findall(r'\((\d+)\) ____',passage) == list(map(str,range(1,count+1)))
    filled = passage
    for q in qs:
        labels = list('ABCD'[:options]); assert [p[0] for p in q['options']] == labels
        assert q['answer'] in labels and len({p[1].casefold().strip() for p in q['options']}) == options
        reasons = dict(part.split('：',1) for part in q['rationale'].split('；'))
        assert set(reasons) == set(labels) and all(reasons.values())
        assert all(v.strip() for _,v in q['options'])
        filled = filled.replace('('+str(q['number'])+') ____',dict(q['options'])[q['answer']])
    assert '____' not in filled
    return passage, filled


def check(group, audit, binding, source):
    draft = json.loads(load_ref(audit['manuscript']).read_text())
    passage, filled = validate(draft,binding,source)
    assert audit['school_complete_cloze'] and audit['student_passage'] == passage and audit['filled_passage'] == filled
    assert group['questions'] == draft['questions'] and group['grade'] == draft['grade']
    if source['configuration'].get('inline_illustrated_glosses'):
        figures=draft['gloss_figures']
        assert audit['school_inline_gloss_cloze']
        assert audit['figure_assets']==[f['asset']for f in figures]
        assert audit['body_load_text']==without_gloss_figures(passage)
        assert audit['load_measure']['body_Han_characters']==len(re.findall('[\u3400-\u9fff]',audit['body_load_text']))
        assert audit['illustrated_gloss_labels']==[f['term']for f in figures]
        assert audit['load_measure']['illustrated_gloss_label_English_words']==sum(len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?",f['term']))for f in figures)
        assert len(group['requiredPassageImages'])==len(figures)==2
        for figure,shown in zip(figures,group['requiredPassageImages']):
            assert shown['asset']==figure['asset'] and shown['alt']==figure['alt']
            assert shown['width']==160 and shown['height']==140
            assert base64.b64decode(shown['src'].split(',',1)[1])==load_ref(figure['asset']).read_bytes()
    if source['configuration']['materials']>1:
        assert len(audit['school_cloze_materials'])==source['configuration']['materials']
        for label,numbers in section_ranges(draft['sections']):
            heading=label+'篇（第'+str(numbers[0])+'—'+str(numbers[-1])+'空）'
            assert heading in group['passageHtml']
    assert len(audit['choice_pair_audit']) == source['responses'] * source['options_each']
    pairs = {(p['number'],p['candidate']):p for p in audit['choice_pair_audit']}
    assert len(pairs) == len(audit['choice_pair_audit'])
    for q in draft['questions']:
        reasons = dict(part.split('：',1) for part in q['rationale'].split('；'))
        for label,value in q['options']:
            p = pairs[(q['number'],label)]; text = passage
            for other in draft['questions']:
                text = text.replace('('+str(other['number'])+') ____',value if other['number']==q['number'] else dict(other['options'])[other['answer']])
            assert p['text']==value and p['full_group_substitution']==text and p['reason']==reasons[label]
            assert p['is_best'] == (label==q['answer'])
    return True
