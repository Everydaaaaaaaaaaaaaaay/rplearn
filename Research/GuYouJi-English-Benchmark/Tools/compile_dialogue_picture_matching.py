#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Five labelled conversations are one complete picture-matching group."""
import argparse
import hashlib
import json
from pathlib import Path
from grade_mode_evidence import REPO, load_ref
from quality_review_contract import response_markdown
from render_original_listening import words
from compile_short_dialogue_listening import ref


def check(group,audit,binding,source):
    selected=json.loads(load_ref(source['selected_native']).read_text())
    assert selected['source']==source['source']and selected['source_images']==source['source_images']
    assert selected['question_numbers']==source['source_question_numbers']==list(range(11,16))and selected['audio_labels']==list('ABCDE')and selected['picture_positions']==5
    assert selected['source_sample_label_preserved']and selected['source_once_only_reuse_not_printed']and selected['source_picture_roles_not_inferred']
    assert not any(source[k]for k in ['source_key_acquired','source_script_acquired','source_original_audio_acquired','source_full_input_verified','original_school_authenticated','region_in_body'])
    d=json.loads(load_ref(audit['manuscript']).read_text());generation=json.loads(load_ref(audit['audio_generation']).read_text());clip=d['clips'][0];track=generation['tracks'][0];asset=audit['audio_assets'][0];display=group['requiredAudioAssets'][0]
    assert generation['manuscript']==audit['manuscript']and generation['whole_final_audio_decode_passed']and generation['no_source_recording_reused']
    assert d['grade']==group['grade']==binding['level']==source['level']=='primary3'and d['source_group_id']==source['id']
    assert len(d['clips'])==len(generation['tracks'])==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==1
    assert len(d['audio_dialogue_units'])==source['materials']==len(group['questions'])==source['responses']==binding['responses']==len(group['requiredPassageImages'])==5
    assert [u['label']for u in d['audio_dialogue_units']]==list('ABCDE')
    expected=[t for u in d['audio_dialogue_units']for t in [dict(speaker='N',text='Dialogue '+u['label']+'.')]+u['turns']]
    assert clip['turns']==expected and d['source_replay_rule']=='not_printed'and d['render_repeat_count']==1
    assert track['response_numbers']==asset['response_numbers']==display['response_numbers']==list(range(1,6))and track['repeat_count']==display['repeat_count']==1
    assert track['sha256']==asset['sha256']==display['asset']['sha256'];load_ref(asset)
    assert [(s['speaker'],s['text'],s['repeat'])for s in track['segments']if s['role']=='dialogue']==[(t['speaker'],t['text'],1)for t in expected]
    assert track['decoded_frames']>0 and track['peak_abs_sample']>0
    for segment in [track['segments'][1],track['segments'][-1]]:assert segment['role']=='silence'and segment['end_frame']-segment['start_frame']==15*track['sample_rate']
    for n,(q,record,fig,img)in enumerate(zip(group['questions'],clip['questions'],d['figures'],group['requiredPassageImages']),1):
        assert q==dict(number=n,**record)and q['options']==[[k,'对话'+k]for k in'ABCDE']and 'bankReuse'not in q
        assert img['asset']==fig and img['alt']=='第'+str(n)+'图';load_ref(fig)
    assert group['fixedSharedBank']and source['features']['reuse_rule']=='not_printed'and '没有额外规定'in group['instruction']
    assert all(t['text']in group['reviewText']and t['text']not in group['passageHtml']for t in expected)
    assert audit['dialogue_picture_matching']and audit['source_unknown_reuse_not_replaced']
    return True


def compile_author(manuscript,version='0.1'):
    manuscript=manuscript.resolve();d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);binding=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding'])
    mp=REPO/'build/english-benchmark-authority-20261017/original-audio'/(d['id']+'-audio-v'+version+'.json');generation=json.loads(mp.read_text());assert generation['manuscript']==ref(manuscript)and generation['whole_final_audio_decode_passed']
    clip=d['clips'][0];track=generation['tracks'][0];audio=load_ref(track);tasks=[dict(number=n,**q)for n,q in enumerate(clip['questions'],1)]
    body=['[A—E五段对话完整音频（本机一遍，可重播）](../../../../'+str(audio.relative_to(REPO))+')']
    for n,figure in enumerate(d['figures'],1):body+=['### 图片'+str(n),'![第'+str(n)+'图](../../../../'+str(load_ref(figure).relative_to(REPO))+')']
    material='\n\n'.join(body);block=response_markdown(tasks)
    teacher='\n\n'.join('### 对话'+u['label']+'完整原创脚本\n\nN: Dialogue '+u['label']+'.\n\n'+'\n\n'.join(t['speaker']+': '+t['text']for t in u['turns'])for u in d['audio_dialogue_units'])
    teacher+='\n\n实际音轨先报Dialogue A—E，每标号后是该段M/W问答，整组只算一完整大题/五回应，不把五段计五套。各图只用图号，不给英文对象名或键；部分自有图形语汇复用，非十五独立主题。\n\n源为三年级期末考试样卷第11—15完整五图与A—E对话标号匹配，不将原文顺序字样改成短文事件排序。源图在库，具体角色/语义不凭缩图猜，正文地域未见，原校施测未认证；源脚本/音轨/键未取得。重播/精确时序/候选复用次数未印；本机一遍、前后15秒为演示，可重播，不加每项一次限制。完整原创不当源gold、儿童识图听辨、目标难度、独立教研、学生、商用或生产验收。\n'
    p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+material+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher)
    asset={k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']}
    audit=dict(version=version,id=d['id'],grade='primary3',questions=5,candidate_sha256=ref(p)['sha256'],source_binding=binding['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=material,body_load_text='',manuscript=ref(manuscript),audio_generation=ref(mp),audio_assets=[asset],figure_assets=d['figures'],visual_panel_semantics=d['visual_panel_semantics'],audio_transcript_in_teacher_only=True,dialogue_picture_matching=True,source_unknown_reuse_not_replaced=True,load_measure=dict(body_English_words=0,stem_English_words=0,options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),output_response_positions=5,audio_dialogue_English_words_once=sum(words(t['text'])for u in d['audio_dialogue_units']for t in u['turns']),audio_label_English_words_once=sum(words('Dialogue '+u['label'])for u in d['audio_dialogue_units']),audio_spoken_words_with_instructions=track['spoken_words_with_instructions'],audio_seconds_with_pauses=track['seconds'],artifact_URLs_and_panel_numbers_excluded_from_reading_load=True,candidate_label_tokens_with_repetition=25,candidate_lexical_English_words=0),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n');return dict(id=d['id'],grade=d['grade'],family=d['family'],family_label=d['family_label'],title=d['title'],questions=5,candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],use_select_controls=True,source_form_notice='小三公开期末样卷完整五对话标号配五图已核；源图在库、脚本/音轨/键缺，重复/复用规则未知。本稿完整原创图音，不加每字母仅一次；非实际施测/儿童识图或独立难度验证。',format_summary='5段A—E短对话 / 5幅图各选对话标号 / 共5回应 / 源复用及遍数未知 / 不作事件时间排序')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manuscript',type=Path,action='append',required=True);p.add_argument('--metadata-output',type=Path,required=True);a=p.parse_args();assert not a.metadata_output.exists();rows=[compile_author(m)for m in a.manuscript];a.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');print(dict(groups=len(rows),responses=5*len(rows)))
