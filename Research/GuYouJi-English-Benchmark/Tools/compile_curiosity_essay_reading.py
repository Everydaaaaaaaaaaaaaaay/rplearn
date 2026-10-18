"""Compile a source-bound complete G8 six-paragraph essay and three four-choice items."""
import json,re
from pathlib import Path
from grade_mode_evidence import load_ref
from compile_short_dialogue_listening import ref
from compile_school_reading import words
from quality_review_contract import response_markdown
from curiosity_essay_reading_contract import validate,digest

def compile_author(manuscript):
 mp=Path(manuscript);d=json.loads(mp.read_text());b=next(b for b in json.loads(load_ref(d['source_bindings']).read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())[b['collection']]if s['id']==b['source_group_id']);body=validate(d,b,s);qs=d['questions'];block=response_markdown(qs)
 teacher=d['source_notice']+'\n\n### 答案与逐项依据\n\n'+'\n\n'.join(str(q['number'])+'. '+q['answer']+'。'+q['rationale']for q in qs)+'\n\n六段全文及五处词注、三题各四候选全部保留，各2分6分。作者自审不等于独立教研、学生、商用或生产验证。'
 cp=mp.with_name(d['id']+'-v0.1.md');ap=mp.with_name(d['id']+'-author-check-v0.1.json');assert not cp.exists()and not ap.exists()
 cp.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
 audit=[]
 for q in qs:
  why=dict(x.split('：',1)for x in q['rationale'].split('；'))
  for label,text in q['options']:audit.append(dict(number=q['number'],label=label,text=text,reason=why[label],is_best=label==q['answer']))
 a=dict(version='0.1',id=d['id'],grade=8,questions=3,candidate_sha256=ref(cp)['sha256'],manuscript=ref(mp),source_bindings=d['source_bindings'],source_binding=b['id'],school_complete_reading_section=True,junior_optional_curiosity_essay3=True,inline_glosses=d['inline_glosses'],essay_paragraphs=6,example_paragraph=3,review_response_tasks=qs,canonical_response_block_sha256=digest(block),student_passage=body,body_load_text=body,question_candidate_audit=audit,load_measure=dict(body_English_words=words(body),body_Han_characters=sum(len(re.findall('[\u3400-\u9fff]',p))for p in d['paragraphs']),stem_English_words=sum(words(q['stem'])for q in qs),stem_Han_characters=0,options_English_words_with_repeated_bank=sum(words(t)for q in qs for k,t in q['options']),options_Han_characters=0,output_response_positions=3,output_requirement_English_words=words(d['instruction']),output_requirement_Han_characters=len(re.findall('[\u3400-\u9fff]',d['instruction'])),inline_glosses_already_in_body=5),source_original_key_not_gold=True,source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
 ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n');return dict(id=d['id'],title=d['title'],grade=8,family='reading_choice',family_label='阅读单选',questions=3,candidate=ref(cp),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary=d['format_summary'])
