"""Whole source-bound cloze examples; source attribution is not school authentication."""
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import load_ref
from compile_short_dialogue_listening import ref
from quality_review_contract import response_markdown


def words(text):
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?", text))


def validate(draft, binding, source):
    assert draft['grade']==binding['level']==source['level']=='primary5'
    assert draft['family']==binding['family']==source['kind']=='choice_cloze'
    assert draft['source_group_id']==binding['source_group_id']==source['id']
    assert hashlib.sha256(json.dumps(source,sort_keys=True,ensure_ascii=False).encode()).hexdigest()==binding['source_record_sha256']
    assert source['full_student_input'] and not source['is_independent_gold']
    assert source['material']['passages']==1 and source['original_exam_section_complete']=='unknown'
    assert source['source_origin_not_verified'] and binding['new_source_count']==0
    count=source['responses'];assert count in [6,8] and binding['responses']==count
    assert source['candidates']['per_response']==[3]*count and binding['options_each']==3
    native=json.loads(load_ref(source['source_native']).read_text())
    observed=next(g for g in native['groups'] if g['id']==source['id'])
    assert [q['source_number'] for q in observed['options']]==source['question_numbers']
    assert len(observed['options'])==count
    assert all([k for k,_ in q['options']]==list('ABC') for q in observed['options'])
    assert observed['original_exam_section_complete']=='unknown_without_originalpaper'
    assert observed['complete_as_presented_in_tutoring_compilation']
    assert observed['published_key']==source['published_key']
    assert re.findall(r'\((\d+)\) ____',draft['passage'])==list(map(str,range(1,count+1)))
    assert len(draft['questions'])==count and [q['number'] for q in draft['questions']]==list(range(1,count+1))
    for q in draft['questions']:
        assert [k for k,_ in q['options']]==list('ABC') and q['answer'] in 'ABC'
        assert len(set(v for _,v in q['options']))==3
        assert all(k+'：' in q['rationale'] for k in 'ABC')
        reasons=dict(part.split('：',1) for part in q['rationale'].split('；'))
        assert set(reasons)==set('ABC') and all(reasons.values())
    filled=draft['passage']
    for q in draft['questions']:
        filled=filled.replace('('+str(q['number'])+') ____',dict(q['options'])[q['answer']])
    assert '____' not in filled
    return filled


def compile_author(manuscript):
    draft=json.loads(manuscript.read_text());bp=load_ref(draft['source_bindings'])
    binding=next(r for r in json.loads(bp.read_text())['bindings'] if r['id']==draft['source_binding'])
    source=next(r for r in json.loads(load_ref(binding['source_index']).read_text())[binding['collection']] if r['id']==binding['source_group_id'])
    filled=validate(draft,binding,source);tasks=draft['questions'];block=response_markdown(tasks)
    candidate=manuscript.with_name(draft['id']+'-v0.1.md');audit_path=manuscript.with_name(draft['id']+'-author-check-v0.1.json')
    assert not candidate.exists() and not audit_path.exists()
    candidate.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+draft['passage']+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+draft['source_notice']+'\n\n### 全组回填\n\n'+filled+'\n')
    pairs=[]
    for q in tasks:
        reasons=dict(part.split('：',1) for part in q['rationale'].split('；'))
        assert set(reasons)==set('ABC')
        pairs += [dict(number=q['number'],candidate=k,text=v,is_best=k==q['answer'],reason=reasons[k])for k,v in q['options']]
    # Substitute by the numbered slot, not by a repeated word in the passage.
    for pair in pairs:
        text=draft['passage']
        for q in tasks:text=text.replace('('+str(q['number'])+') ____',pair['text'] if q['number']==pair['number'] else dict(q['options'])[q['answer']])
        pair['full_group_substitution']=text
    audit=dict(version='0.1',id=draft['id'],grade=draft['grade'],questions=len(tasks),candidate_sha256=ref(candidate)['sha256'],source_binding=binding['id'],source_bindings=ref(bp),source_group_id=source['id'],manuscript=ref(manuscript),review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=draft['passage'],filled_passage=filled,inherited_complete_cloze=True,choice_pair_audit=pairs,load_measure=dict(body_English_words=words(draft['passage']),body_Han_characters=len(re.findall('[\u3400-\u9fff]',draft['passage'])),stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),output_response_positions=len(tasks)),source_count_increment=0,authored_student_inputs_complete=True,source_original_exam_whole_section_authenticated=False,independent_teacher_student_commercial_production_validated=False)
    audit_path.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=draft['id'],grade=draft['grade'],family=draft['family'],family_label='单选完形',title=draft['title'],questions=len(tasks),candidate=ref(candidate),author_check=ref(audit_path),source_group_ids=[source['id']],instruction=draft['instruction'],source_form_notice=draft['source_notice'],format_summary='1完整语篇 / '+str(len(tasks))+'空各3候选 / 每空独立候选 / 无已解示例 / 完整教辅例参照、原校整节未知')


def check(group,audit,binding,source):
    draft=json.loads(load_ref(audit['manuscript']).read_text());filled=validate(draft,binding,source)
    assert audit['filled_passage']==filled and group['questions']==draft['questions']
    assert group['passageHtml'] and audit['inherited_complete_cloze']
    pairs=audit['choice_pair_audit'];assert len(pairs)==source['responses']*3
    for q in draft['questions']:
        for k,v in q['options']:
            p=next(p for p in pairs if p['number']==q['number'] and p['candidate']==k)
            text=draft['passage']
            for other in draft['questions']:text=text.replace('('+str(other['number'])+') ____',v if q['number']==other['number'] else dict(other['options'])[other['answer']])
            reasons=dict(part.split('：',1) for part in q['rationale'].split('；'))
            assert p['full_group_substitution']==text and p['is_best']==(k==q['answer']) and p['reason']==reasons[k]
    return True
