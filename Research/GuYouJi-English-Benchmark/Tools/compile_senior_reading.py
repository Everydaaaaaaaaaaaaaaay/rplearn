"""Compile an observed complete senior section and separate input-load measures."""
import json
import re
from pathlib import Path
from compile_short_dialogue_listening import ref
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_school_reading import words
from senior_reading_contract import validate,digest,body_text,table_markup,unit_load_text


def compile_author(manuscript, version='0.1'):
    mp=Path(manuscript);d=json.loads(mp.read_text());bp=load_ref(d['source_bindings'])
    b=next(x for x in json.loads(bp.read_text())['bindings']if x['id']==d['source_binding'])
    s=next(x for x in json.loads(load_ref(b['source_index']).read_text())['groups']if x['id']==b['source_group_id'])
    passage=validate(d,b,s);qs=d['questions'];block=response_markdown(qs);c=s['configuration']
    teacher=d['source_notice']+'\n\n### 答案与逐项依据\n\n'+'\n\n'.join(str(q['number'])+'. '+q['answer']+'。'+q['rationale']for q in qs)+'\n\n全'+str(len(qs))+'题及全部材料保留；每题'+str(c['points_each'])+'分，共'+str(c['selected_objective_points'])+'分。作者依据为模型自审，不当独立教研、学生、商用或生产验证。'
    cp=mp.with_name(d['id']+'-v'+version+'.md');ap=mp.with_name(d['id']+'-author-check-v'+version+'.json')
    assert not cp.exists() and not ap.exists()
    cp.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
    body=body_text(d);audits=[]
    for q in qs:
        reasons=dict(x.split('：',1)for x in q['rationale'].split('；'))
        for label,text in q['options']:
            audits.append(dict(number=q['number'],label=label,text=text,is_best=label==q['answer'],reason=reasons[label],material_label=q['materialLabel']))
    audit=dict(version=version,id=d['id'],grade=d['grade'],questions=len(qs),candidate_sha256=ref(cp)['sha256'],manuscript=ref(mp),source_bindings=ref(bp),source_binding=b['id'],school_complete_senior_reading_section=True,review_response_tasks=qs,canonical_response_block_sha256=digest(block),student_passage=passage,body_load_text=body,question_candidate_audit=audits,subgroup_response_counts=c['response_distribution'],subgroup_material_units=[x['material_units']for x in c['subgroups']],material_unit_load=[dict(label=x['label'],intro_words=words(x.get('intro','')),words=[words(unit_load_text(d,u))for u in x['units']])for x in d['sections']],load_measure=dict(body_English_words=words(body),body_Han_characters=len(re.findall('[\u3400-\u9fff]',body)),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=sum(words(t)for q in qs for _,t in q['options']),options_Han_characters=0,output_response_positions=len(qs),output_requirement_English_words=words(d['instruction']),display_material_label_English_words=len(d['sections'])+c['text_unit_count']),source_original_key_not_gold=True,source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
    if d.get('source_bound_graph_reading_section'):
        from senior_graph_reading_contract import graph_alt
        model=d['graph_model']
        audit.update(source_bound_graph_reading_section=True,graph_asset=d['graph_asset'],
                     graph_model=model,mechanism_evidence=d['mechanism_evidence'],
                     hearing_evidence=d['hearing_evidence'],answer_evidence=d['answer_evidence'])
        audit['load_measure'].update(graph_label_English_words=words(' '.join([model['title'],model['x_axis'],model['y_axis'],'Low High']+model['point_labels'])),
                                    graph_alt_English_words=words(graph_alt(model)),necessary_curve_graphs=1,
                                    graph_markup_excluded_from_body_count=True)
    if d.get('source_bound_care_notice14_section'):
        audit.update(source_bound_care_notice14_section=True,care_notice=d['care_notice'],
                     experience_options=d['experience_options'],narrative_evidence=d['narrative_evidence'],
                     answer_evidence=d['answer_evidence'])
        audit['load_measure'].update(notice_required_fields=5,research_accounts=2,
                                    output_requirement_Han_characters=len(re.findall('[\u3400-\u9fff]',d['instruction'])),
                                    stem_Han_characters=sum(len(re.findall('[\u3400-\u9fff]',q['stem']))for q in qs))
    if d.get('source_bound_native14_profile_research_section'):
        audit.update(source_bound_native14_profile_research_section=True,
                     volunteer_notice=d['volunteer_notice'],illustrative_media=d['illustrative_media'],
                     figure_assets=[m['asset']for m in d['illustrative_media']],
                     bird_study=d['bird_study'],meal_study=d['meal_study'],answer_evidence=d['answer_evidence'])
        audit['load_measure'].update(notice_bullet_sections=3,notice_bullet_entries=12,
                                    illustrative_images=2,illustrative_images_not_response_coded=True,
                                    image_caption_English_words=sum(words(m['caption'])for m in d['illustrative_media']),
                                    image_alt_English_words=sum(words(m['alt'])for m in d['illustrative_media']),
                                    image_markup_and_captions_excluded_from_body=True,
                                    output_requirement_Han_characters=len(re.findall('[\u3400-\u9fff]',d['instruction'])))
    if d.get('credit_notice'):
        from senior_credit_reading_contract import format_credit
        policy=d['credit_notice']
        audit.update(source_bound_credit_notice_reading_section=True,credit_notice=policy)
        audit['load_measure'].update(compulsory_credit_entries=len(policy['compulsory']),half_credit_entries=sum(x['credits']==0.5 for x in policy['compulsory']),online_nested_credits=policy['online_credits'],community_hours_not_credits=policy['community_hours'])
    if d.get('program_policy'):
        audit.update(source_bound_four_program_reading_section=True,program_policy=d['program_policy'],program_match=d['program_match'],research_conditions=d['research_conditions'])
    if d.get('job_notice'):
        audit.update(source_bound_job_notice_reading_section=True,job_notice=d['job_notice'],
                     applicant_options=d['applicant_options'],survey=d['survey'],robot=d['robot'],
                     answer_evidence=d['answer_evidence'])
        audit['load_measure'].update(job_advert_subheadings=6,minimum_license_years_inclusive=3,
                                    pay_every_weeks=2,weekly_pay750_not_monthly=True)
    if d.get('source_bound_steps_letter_migration_survey'):
        audit.update(source_bound_steps_letter_migration_survey=True,
                     steps=d['steps'],letter=d['letter'],migration=d['migration'],
                     survey=d['survey'],answer_evidence=d['answer_evidence'])
        audit['load_measure'].update(ordered_advice_steps=4,complete_private_letter=1,
                                    migration_units=['captured_individuals','sampled_individuals','tracked_individuals','completed_flights'],
                                    survey_scales=['0 to 10','1 to 3'])
    if d.get('required_table'):
        audit.update(required_table=d['required_table'],fee_comparison=d['fee_comparison'],lexical_paragraph=d['lexical_paragraph'],source_bound_three_passage_fee_table_section=True)
        audit['load_measure'].update(table_English_words_in_body=words(table_markup(d['required_table'])),table_numeric_cells=6,table_data_rows=3,table_value_columns=2)
    ap.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],title=d['title'],grade=d['grade'],family=d['family'],family_label='阅读单选',questions=len(qs),candidate=ref(cp),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary=d['format_summary'])
