"""Compile complete G8 device-bank/narrative/report11 with four-choice responses."""
import json,re
from pathlib import Path
from grade_mode_evidence import load_ref
from compile_short_dialogue_listening import ref
from compile_school_reading import words
from quality_review_contract import response_markdown
from device_reading_contract import validate,digest,body_text

def compile_author(manuscript):
 mp=Path(manuscript);d=json.loads(mp.read_text());b=next(b for b in json.loads(load_ref(d['source_bindings']).read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())[b['collection']]if s['id']==b['source_group_id']);passage=validate(d,b,s);body=body_text(d);qs=d['questions'];block=response_markdown(qs)
 teacher=d['source_notice']+'\n\n### 答案与逐项依据\n\n'+'\n\n'.join(str(q['number'])+'. '+q['answer']+'。'+q['rationale']for q in qs)+'\n\n完整A配图3＋B叙事4＋C报告4共11题，各四候选，各2分22分；只A共享图片，不强加复用禁令。作者自审不等于独立教研、学生、商用或生产验证。'
 cp=mp.with_name(d['id']+'-v0.1.md');ap=mp.with_name(d['id']+'-author-check-v0.1.json');assert not cp.exists()and not ap.exists()
 cp.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
 audit=[]
 for q in qs:
  why=dict(x.split('：',1)for x in q['rationale'].split('；'))
  for label,text in q['options']:audit.append(dict(number=q['number'],label=label,text=text,reason=why[label],is_best=label==q['answer']))
 han=lambda t:len(re.findall('[\u3400-\u9fff]',t));numeric=lambda t:re.findall(r'\d+(?:[:.]\d+)?',t)
 load=dict(body_English_words=words(body),body_Han_characters=han(body),stem_English_words=sum(words(q['stem'])for q in qs),stem_Han_characters=sum(han(q['stem'])for q in qs),options_English_words_with_repeated_bank=sum(words(t)for q in qs for k,t in q['options']),options_Han_characters=sum(han(t)for q in qs for k,t in q['options']),output_response_positions=11,output_requirement_English_words=words(d['instruction']),output_requirement_Han_characters=han(d['instruction']),body_numeric_literals=numeric(body),B_words=sum(words(t)for t in d['B_paragraphs']),C_words=sum(words(t)for t in d['C_paragraphs']),profile_words=sum(words(p['name']+' '+p['text'])for p in d['profiles']),B_inline_glosses=4,C_inline_glosses=5,glosses_already_in_body_not_added_twice=True,shared_device_picture_panels=4,profile_faces=3,image_resource_count=4,visible_grid_choice_label_words=4,visible_grid_numeric_strings=['026','08:00'],alt_English_words=sum(words(m['alt'])for m in d['media']),alt_Han_characters=sum(han(m['alt'])for m in d['media']),candidate_positions_with_shared_repeat=44,candidate_displays_shared_once=36,section_letter_labels3_and_profile_numbers3_not_body_words=True)
 a=dict(version='0.1',id=d['id'],grade=8,questions=11,candidate_sha256=ref(cp)['sha256'],manuscript=ref(mp),source_bindings=d['source_bindings'],source_binding=b['id'],school_complete_reading_section=True,junior_shared_device_picture_reading11=True,queried_phrase=d['queried_phrase'],figure_assets=[m['asset']for m in d['media']],review_response_tasks=qs,canonical_response_block_sha256=digest(block),student_passage=passage,body_load_text=body,question_candidate_audit=audit,subgroup_response_counts=[3,4,4],subgroup_material_units=[3,1,1],load_measure=load,source_original_key_not_gold=True,source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
 ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n');return dict(id=d['id'],title=d['title'],grade=8,family='mixed_closed_reading',family_label='闭集阅读组合',questions=11,candidate=ref(cp),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary=d['format_summary'])
