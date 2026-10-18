"""Compile one complete, source-bound school cloze manuscript without clipping."""
import json
import re
from pathlib import Path
from compile_short_dialogue_listening import ref
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from school_cloze_contract import digest, validate


def words(text):
    return len(re.findall(r"[A-Za-z]+(?:['’][A-Za-z]+)?",text))


def compile_author(manuscript):
    manuscript=Path(manuscript)
    draft=json.loads(manuscript.read_text())
    bp=load_ref(draft['source_bindings'])
    binding=next(b for b in json.loads(bp.read_text())['bindings'] if b['id']==draft['source_binding'])
    source=next(s for s in json.loads(load_ref(binding['source_index']).read_text())[binding['collection']] if s['id']==binding['source_group_id'])
    passage,filled=validate(draft,binding,source)
    qs=draft['questions'];block=response_markdown(qs)
    teacher=draft['source_notice']+'\n\n### 答案与逐项依据\n\n'+'\n\n'.join(str(q['number'])+'. '+q['answer']+'。'+q['rationale']for q in qs)+'\n\n### 全组回填\n\n'+filled+'\n\n原样本支持具体材料篇数、空数、候选与分值。本稿篇幅单独计量，不从单卷推出全国词数范围、难度或用时等值、年级排他性。所有角色与事件虚构，作者自审不替代独立教研、学生、商用和生产验证。'
    text='# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n'
    candidate=manuscript.with_name(draft['id']+'-v0.1.md');ap=manuscript.with_name(draft['id']+'-author-check-v0.1.json')
    assert not candidate.exists() and not ap.exists(),'Frozen authored versions must not be overwritten'
    candidate.write_text(text)
    pairs=[]
    for q in qs:
        reasons=dict(z.split('：',1)for z in q['rationale'].split('；'))
        for label,value in q['options']:
            full=passage
            for other in qs:
                full=full.replace('('+str(other['number'])+') ____',value if q['number']==other['number'] else dict(other['options'])[other['answer']])
            pairs.append(dict(number=q['number'],candidate=label,text=value,is_best=label==q['answer'],reason=reasons[label],full_group_substitution=full))
    audit=dict(version='0.1',id=draft['id'],grade=draft['grade'],questions=len(qs),candidate_sha256=ref(candidate)['sha256'],source_bindings=ref(bp),source_binding=binding['id'],manuscript=ref(manuscript),source_count_increment=0,school_complete_cloze=True,review_response_tasks=qs,canonical_response_block_sha256=digest(block),student_passage=passage,filled_passage=filled,choice_pair_audit=pairs,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False,source_key_not_copied=True,load_measure=dict(body_English_words=words(passage),body_Han_characters=len(re.findall('[\u3400-\u9fff]',passage)),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=sum(words(v)for q in qs for _,v in q['options']),output_response_positions=len(qs),output_requirement_English_words=words(draft['instruction'])))
    ap.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=draft['id'],title=draft['title'],grade=draft['grade'],family=draft['family'],family_label='单选完形',questions=len(qs),candidate=ref(candidate),author_check=ref(ap),source_group_ids=[source['id']],instruction=draft['instruction'],source_form_notice=draft['source_notice'],format_summary=draft['format_summary'])
