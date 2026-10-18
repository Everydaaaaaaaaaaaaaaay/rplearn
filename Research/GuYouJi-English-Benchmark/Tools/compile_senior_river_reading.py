"""Compile source-bound senior caves/friendship/river/forecast whole15."""
import json,re
from pathlib import Path
from compile_short_dialogue_listening import ref
from grade_mode_evidence import load_ref
from compile_school_reading import words
from quality_review_contract import response_markdown
from senior_river_reading_contract import validate,digest
from senior_reading_contract import body_text

def compile_author(manuscript):
 mp=Path(manuscript);d=json.loads(mp.read_text());b=next(b for b in json.loads(load_ref(d['source_bindings']).read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())[b['collection']]if s['id']==b['source_group_id']);passage=validate(d,b,s);qs=d['questions'];block=response_markdown(qs)
 teacher=d['source_notice']+'\n\n### 答案与逐项依据\n\n'+'\n\n'.join(str(q['number'])+'. '+q['answer']+'。'+q['rationale']for q in qs)+'\n\n全15题、四洞穴简介及导语、友情报道、河流城市史编号和未来车载预测说明保留；每题2.5分，共37.5分，不含另节阅读。作者自审，不当独立教研、学生、商用或生产验证。'
 cp=mp.with_name(d['id']+'-v0.1.md');ap=mp.with_name(d['id']+'-author-check-v0.1.json');assert not cp.exists()and not ap.exists();cp.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
 body=body_text(d);audit=[]
 for q in qs:
  why=dict(x.split('：',1)for x in q['rationale'].split('；'))
  for label,text in q['options']:audit.append(dict(number=q['number'],label=label,text=text,reason=why[label],is_best=label==q['answer']))
 a=dict(version='0.1',id=d['id'],grade=12,questions=15,candidate_sha256=ref(cp)['sha256'],manuscript=ref(mp),source_bindings=d['source_bindings'],source_binding=b['id'],school_complete_reading_section=True,senior_caves_friendship_river_forecast15=True,friendship=d['friendship'],river=d['river'],forecast=d['forecast'],review_response_tasks=qs,canonical_response_block_sha256=digest(block),student_passage=passage,body_load_text=body,question_candidate_audit=audit,subgroup_response_counts=[3,4,4,4],subgroup_material_units=[4,1,1,1],load_measure=dict(body_English_words=words(body),body_Han_characters=0,stem_English_words=sum(words(q['stem'])for q in qs),stem_Han_characters=15,options_English_words_with_repeated_bank=sum(words(t)for q in qs for _,t in q['options']),options_Han_characters=0,output_response_positions=15,output_requirement_English_words=words(d['instruction']),output_requirement_Han_characters=len(re.findall('[\u3400-\u9fff]',d['instruction'])),A_cave_profiles=4,A_intro_English_words=words(d['sections'][0]['intro']),forecast_paragraphs=6),source_original_key_not_gold=True,source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
 ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n');return dict(id=d['id'],title=d['title'],grade=12,family='reading_choice',family_label='阅读单选',questions=15,candidate=ref(cp),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary=d['format_summary'])
