"""Compile an observed complete senior section and separate input-load measures."""
import json
import re
from pathlib import Path
from compile_short_dialogue_listening import ref
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_school_reading import words
from senior_reading_contract import validate,digest,body_text


def compile_author(manuscript):
    mp=Path(manuscript);d=json.loads(mp.read_text());bp=load_ref(d['source_bindings'])
    b=next(x for x in json.loads(bp.read_text())['bindings']if x['id']==d['source_binding'])
    s=next(x for x in json.loads(load_ref(b['source_index']).read_text())['groups']if x['id']==b['source_group_id'])
    passage=validate(d,b,s);qs=d['questions'];block=response_markdown(qs);c=s['configuration']
    teacher=d['source_notice']+'\n\n### 答案与逐项依据\n\n'+'\n\n'.join(str(q['number'])+'. '+q['answer']+'。'+q['rationale']for q in qs)+'\n\n全'+str(len(qs))+'题及全部材料保留；每题'+str(c['points_each'])+'分，共'+str(c['selected_objective_points'])+'分。作者依据为模型自审，不当独立教研、学生、商用或生产验证。'
    cp=mp.with_name(d['id']+'-v0.1.md');ap=mp.with_name(d['id']+'-author-check-v0.1.json')
    assert not cp.exists() and not ap.exists()
    cp.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
    body=body_text(d);audits=[]
    for q in qs:
        reasons=dict(x.split('：',1)for x in q['rationale'].split('；'))
        for label,text in q['options']:
            audits.append(dict(number=q['number'],label=label,text=text,is_best=label==q['answer'],reason=reasons[label],material_label=q['materialLabel']))
    audit=dict(version='0.1',id=d['id'],grade=d['grade'],questions=len(qs),candidate_sha256=ref(cp)['sha256'],manuscript=ref(mp),source_bindings=ref(bp),source_binding=b['id'],school_complete_senior_reading_section=True,review_response_tasks=qs,canonical_response_block_sha256=digest(block),student_passage=passage,body_load_text=body,question_candidate_audit=audits,subgroup_response_counts=c['response_distribution'],subgroup_material_units=[x['material_units']for x in c['subgroups']],material_unit_load=[dict(label=x['label'],intro_words=words(x.get('intro','')),words=[words(u)for u in x['units']])for x in d['sections']],load_measure=dict(body_English_words=words(body),body_Han_characters=len(re.findall('[\u3400-\u9fff]',body)),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=sum(words(t)for q in qs for _,t in q['options']),options_Han_characters=0,output_response_positions=len(qs),output_requirement_English_words=words(d['instruction']),display_material_label_English_words=len(d['sections'])+c['text_unit_count']),source_original_key_not_gold=True,source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],title=d['title'],grade=d['grade'],family=d['family'],family_label='阅读单选',questions=len(qs),candidate=ref(cp),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary=d['format_summary'])
