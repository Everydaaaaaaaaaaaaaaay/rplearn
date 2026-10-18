"""Compile a whole closed reading11 with four shared cards and six owned figures."""
import json,re
from pathlib import Path
from compile_short_dialogue_listening import ref
from grade_mode_evidence import load_ref
from compile_school_reading import words
from quality_review_contract import response_markdown
from mixed_closed_reading_contract import validate,digest,body_text

def compile_author(manuscript,version='0.1'):
 mp=Path(manuscript);d=json.loads(mp.read_text());b=next(b for b in json.loads(load_ref(d['source_bindings']).read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())[b['collection']]if s['id']==b['source_group_id']);passage=validate(d,b,s);qs=d['questions'];block=response_markdown(qs)
 teacher=d['source_notice']+'\n\n### 答案与逐项依据\n\n'+'\n\n'.join(str(q['number'])+'. '+q['answer']+'。'+q['rationale']for q in qs)+'\n\n完整3+4+4共11题，各2分22分；开放读答另节暂停，不以单独配对3代整组。作者自审不等于独立教研、学生、商用或生产验证。'
 cp=mp.with_name(d['id']+'-v'+version+'.md');ap=mp.with_name(d['id']+'-author-check-v'+version+'.json');assert not cp.exists()and not ap.exists()
 cp.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
 body=body_text(d);audit=[]
 for q in qs:
  why=dict(x.split('：',1)for x in q['rationale'].split('；'))
  for label,text in q['options']:audit.append(dict(number=q['number'],label=label,text=text,reason=why[label],is_best=label==q['answer']))
 bank=' '.join(c['text']+' '+c['title']+' '+c['time']+' '+c['place']for c in d['cards'])
 a=dict(version=version,id=d['id'],grade=7,questions=11,candidate_sha256=ref(cp)['sha256'],manuscript=ref(mp),source_bindings=d['source_bindings'],source_binding=b['id'],school_complete_reading_section=True,school_closed_mixed_reading11=True,underlined_phrase=d['underlined_phrase'],figure_assets=[m['asset']for m in d['media']],review_response_tasks=qs,canonical_response_block_sha256=digest(block),student_passage=passage,body_load_text=body,question_candidate_audit=audit,subgroup_response_counts=[3,4,4],subgroup_material_units=[7,1,1],load_measure=dict(body_English_words=words(body),body_Han_characters=0,stem_English_words=sum(words(q['stem'])for q in qs),stem_Han_characters=sum(len(re.findall('[\u3400-\u9fff]',q['stem']))for q in qs),options_English_words_with_repeated_bank=sum(words(t)for q in qs for _,t in q['options']),options_Han_characters=sum(len(re.findall('[\u3400-\u9fff]',t))for q in qs for k,t in q['options']),output_response_positions=11,output_requirement_English_words=words(d['instruction']),output_requirement_Han_characters=len(re.findall('[\u3400-\u9fff]',d['instruction'])),activity_bank_words_already_in_body=words(bank),activity_grid_cells=4,profile_faces=3,gloss_words2_already_in_body=True,required_figures=6,picture_text_already_in_body_not_added_twice=True,candidate_positions_with_shared_repeated=36,candidate_displays_with_shared_counted_once=28),source_original_key_not_gold=True,source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
 ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n');return dict(id=d['id'],title=d['title'],grade=7,family='mixed_closed_reading',family_label='闭集阅读组合',questions=11,candidate=ref(cp),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary=d['format_summary'])
