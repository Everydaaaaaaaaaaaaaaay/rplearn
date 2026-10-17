#!/usr/bin/env python3
"""Bind every owned image and spoken sentence to a whole source-bound picture-judgement form."""
import argparse
import hashlib
import json
import xml.etree.ElementTree as ET
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown
from render_original_listening import words
from compile_short_dialogue_listening import ref


def check(group,audit,binding,source):
    size=source['responses']
    assert (source['level'],size)in {('primary3',10),('primary6',9)}
    selected=json.loads(load_ref(source['selected_native']).read_text());assert selected['source']==source['source']and selected['source_images']==source['source_images']
    assert selected['question_numbers']==source['source_question_numbers']==list(range(1,size+1))and selected['options']==['T','F']and selected['pictures_per_response']==1
    if source['level']=='primary3':assert source['sample_paper_not_confirmed_administered']and selected['source_sample_label_preserved']and not source['region_in_body']
    else:assert source['region_in_body']and selected['body_grade_region_term_observed']and not source['sample_paper_not_confirmed_administered']
    assert source['features']['repeats']is None and selected['repeats_and_timing_not_printed']
    assert not any(source[k]for k in ['source_key_acquired','source_script_acquired','source_original_audio_acquired','source_full_input_verified','original_school_authenticated'])
    d=json.loads(load_ref(audit['manuscript']).read_text());generation=json.loads(load_ref(audit['audio_generation']).read_text())
    assert generation['manuscript']==audit['manuscript']and generation['whole_final_audio_decode_passed']and generation['no_source_recording_reused']
    if generation.get('media_only_manuscript_revision'):
        oldgen=json.loads(load_ref(generation['previous_audio_manifest']).read_text());old=json.loads(load_ref(oldgen['manuscript']).read_text())
        assert generation['tracks']==oldgen['tracks']and generation['spoken_content_and_audio_bytes_unchanged']
        assert d['clips']==old['clips']and d['speakers']==old['speakers']and d['render_repeat_count']==old['render_repeat_count']
    assert d['source_group_id']==source['id']and d['grade']==group['grade']==binding['level']==source['level']
    assert len(d['clips'])==len(d['figures'])==len(group['questions'])==len(group['requiredAudioAssets'])==len(group['requiredPassageImages'])==size
    assert d['source_replay_rule']=='not_printed'and d['render_repeat_count']==1
    for n,(clip,track,asset,shown,fig,img)in enumerate(zip(d['clips'],generation['tracks'],audit['audio_assets'],group['requiredAudioAssets'],d['figures'],group['requiredPassageImages']),1):
        assert len(clip['turns'])==len(clip['questions'])==1 and clip['turns'][0]['speaker']=='N'
        assert track['response_numbers']==asset['response_numbers']==shown['response_numbers']==[n]and track['repeat_count']==shown['repeat_count']==1
        assert track['sha256']==asset['sha256']==shown['asset']['sha256'];load_ref(asset)
        heard=[s for s in track['segments']if s['role']=='dialogue'];assert len(heard)==1 and heard[0]['text']==clip['turns'][0]['text']and heard[0]['repeat']==1
        for segment,seconds in [(track['segments'][1],2),(track['segments'][-1],3)]:assert segment['role']=='silence'and segment['end_frame']-segment['start_frame']==seconds*track['sample_rate']
        assert track['decoded_frames']>0 and track['peak_abs_sample']>0
        assert img['asset']==fig and img['alt']=='第'+str(n)+'图'
        svg=ET.fromstring(load_ref(fig).read_bytes());assert svg.attrib['viewBox']=='0 0 224 224'
        assert ''.join(svg.itertext()).strip() not in {'T','F'}
        q=clip['questions'][0];assert group['questions'][n-1]==dict(number=n,**q)and [k for k,_ in q['options']]==['T','F']
        assert clip['turns'][0]['text']in group['reviewText']and clip['turns'][0]['text']not in group['passageHtml']
    assert audit['picture_listening']and audit['audio_transcript_in_teacher_only']and audit['source_timing_unknown_preserved']
    return True


def compile_author(manuscript,version='0.1'):
    manuscript=manuscript.resolve();d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);binding=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding'])
    mp=REPO/'build/english-benchmark-authority-20261017/original-audio'/(d['id']+'-audio-v'+version+'.json');generation=json.loads(mp.read_text());assert generation['manuscript']==ref(manuscript)and generation['whole_final_audio_decode_passed']
    body=[];teacher=[];tasks=[];assets=[]
    for n,(clip,track,figure)in enumerate(zip(d['clips'],generation['tracks'],d['figures']),1):
        fp=load_ref(figure);audio=load_ref(track)
        body+=['### 图片'+str(n),'![第'+str(n)+'图](../../../../'+str(fp.relative_to(REPO))+')','[第'+str(n)+'句（本机一遍，可重播）](../../../../'+str(audio.relative_to(REPO))+')']
        tasks.append(dict(number=n,**clip['questions'][0]));assets.append({k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']});teacher.append('第'+str(n)+'句原创脚本：'+clip['turns'][0]['text'])
    teacher+=d.get('teacher_source_notices',['完整10图/10句/10判断，不把十个图位各算一组。原始图形语汇部分复用自有几何绘制，三组图位不等30独立主题/曝光样本。题图不写对象英文名称或键，所有句子脚本仅解析可见。', '来源为公开期末考试样卷，正文确认三年级/2025—2026上期，未标地区；不凭文件名补东城或实际施测认证。源录音/脚本/参考键未取得；未印重播与停顿。本机每句一遍、前2秒后3秒是演示安排，可重播，不当原卷限制。图音形式完整不等难度、儿童识图/听辨、独立教研、学生、商用或生产验证。'])
    passage='\n\n'.join(body);block=response_markdown(tasks);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists()
    p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
    audit=dict(version=version,id=d['id'],grade=d['grade'],questions=len(tasks),candidate_sha256=ref(p)['sha256'],source_binding=binding['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=passage,body_load_text='',manuscript=ref(manuscript),audio_generation=ref(mp),audio_assets=assets,figure_assets=d['figures'],required_visual_panels=len(tasks),audio_transcript_in_teacher_only=True,picture_listening=True,source_timing_unknown_preserved=True,load_measure=dict(body_English_words=0,stem_English_words=0,options_English_words_with_repeated_bank=0,output_response_positions=len(tasks),audio_dialogue_English_words_once=sum(t['dialogue_words_once']for t in generation['tracks']),audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions']for t in generation['tracks']),audio_seconds_with_pauses=sum(t['seconds']for t in generation['tracks']),artifact_URLs_and_panel_numbers_excluded_from_reading_load=True),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade=d['grade'],family=d['family'],family_label=d['family_label'],title=d['title'],questions=len(tasks),candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],source_form_notice=d.get('source_form_notice','小三公开期末样卷完整10句/10图/T-F结构已核，非实际施测认证；源音轨/脚本/键缺，遍数停顿未知。这里提供完整原创图音与依据；图形语汇部分复用，儿童识图/难度未验证。'),format_summary=d.get('format_summary','10独立句+10对应图 / 共10个T-F回应 / 源播放与停顿未知 / 本机每句一遍可重播'))


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manuscript',type=Path,action='append',required=True);p.add_argument('--metadata-output',type=Path,required=True);a=p.parse_args();assert not a.metadata_output.exists();rows=[compile_author(m)for m in a.manuscript];a.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');print(dict(groups=len(rows),responses=sum(m['questions']for m in rows)))
