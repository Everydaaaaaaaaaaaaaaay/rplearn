#!/usr/bin/env python3
"""Compile whole sentence word/phrase listening; preserve partial source script status."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown
from render_original_listening import words
from compile_short_dialogue_listening import ref


def check(group,audit,binding,source):
    selected=json.loads(load_ref(source['selected_native']).read_text());assert selected['source_HTML']==source['source'];raw=load_ref(selected['source_native']).read_text()
    for name in ['student_span','script_view_span','key_span']:
        span=selected[name];assert hashlib.sha256(raw[span['start']:span['end']].encode()).hexdigest()==span['sha256']
    assert selected['reference_keys']==re.findall('[ABC]',raw[selected['key_span']['start']:selected['key_span']['end']])==list('BABCBBAABC')
    printed=raw[selected['student_span']['start']:selected['student_span']['end']]
    assert len(selected['options'])==10 and all(len(v)==3 for v in selected['options'])and all(v in printed for row in selected['options']for v in row)
    assert '每小题读两遍'in printed and selected['script_has_truncated_tenth_sentence']and 'e and take a helicopter ride!'in raw
    assert source['source_tenth_script_fragment_not_reconstructed']and not source['source_complete_script_verified']and not source['source_original_audio_acquired']and not source['source_full_input_verified']
    assert source['region_body_unknown']and not selected['region_in_body']and not source['original_school_authenticated']
    d=json.loads(load_ref(audit['manuscript']).read_text());generation=json.loads(load_ref(audit['audio_generation']).read_text())
    assert generation['manuscript']==audit['manuscript']and generation['whole_final_audio_decode_passed']and generation['no_source_recording_reused']
    assert d['source_group_id']==source['id']and d['grade']==group['grade']==binding['level']==source['level']=='primary5'
    assert len(d['clips'])==len(group['questions'])==len(group['requiredAudioAssets'])==source['responses']==10
    assert d['source_hear_each_piece_twice']and source['features']['repeat_count']==2
    for n,(clip,track,asset,shown)in enumerate(zip(d['clips'],generation['tracks'],audit['audio_assets'],group['requiredAudioAssets']),1):
        assert len(clip['turns'])==len(clip['questions'])==1 and clip['turns'][0]['speaker']=='N'
        assert track['response_numbers']==asset['response_numbers']==shown['response_numbers']==[n]and track['repeat_count']==shown['repeat_count']==2
        assert track['sha256']==asset['sha256']==shown['asset']['sha256'];load_ref(asset)
        heard=[s for s in track['segments']if s['role']=='dialogue'];assert [(s['text'],s['repeat'])for s in heard]==[(clip['turns'][0]['text'],1),(clip['turns'][0]['text'],2)]
        for segment,seconds in [(track['segments'][1],2),(track['segments'][-1],3)]:assert segment['role']=='silence'and segment['end_frame']-segment['start_frame']==seconds*track['sample_rate']
        assert track['decoded_frames']>0 and track['peak_abs_sample']>0
        q=clip['questions'][0];assert group['questions'][n-1]==dict(number=n,**q)and [k for k,_ in q['options']]==['A','B','C']
        text=clip['turns'][0]['text'];assert text in group['reviewText']and text not in group['passageHtml']
        hits=[k for k,v in q['options']if re.search(r'(?<![A-Za-z])'+re.escape(v)+r'(?![A-Za-z])',text,re.I)];assert hits==[q['answer']]
    assert audit['word_phrase_listening']and audit['audio_transcript_in_teacher_only']and audit['source_partial_script_visible']
    return True


def compile_author(manuscript,version='0.1'):
    manuscript=manuscript.resolve();d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);binding=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding'])
    mp=REPO/'build/english-benchmark-authority-20261017/original-audio'/(d['id']+'-audio-v'+version+'.json');generation=json.loads(mp.read_text());assert generation['manuscript']==ref(manuscript)and generation['whole_final_audio_decode_passed']
    body=[];teacher=[];tasks=[];assets=[]
    for n,(clip,track)in enumerate(zip(d['clips'],generation['tracks']),1):
        audio=load_ref(track);body+=['### 句子'+str(n),'[第'+str(n)+'句（两遍）](../../../../'+str(audio.relative_to(REPO))+')'];tasks.append(dict(number=n,**clip['questions'][0]));assets.append({k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']});teacher.append('第'+str(n)+'句完整原创脚本：'+clip['turns'][0]['text'])
    teacher += ['源为2024—2025下学期小五外研版一年级起点期末学业质量检测公开转载，完整第一题10句/每题3选/句中辨词或短语/每题两遍；每题1分共10分明文。桂林象山地域仅公开标题，正文未核该地域；原学校/施测身份未认证。', '源题面、参考键与印本脚本视图在库，脚本第十句开头截断，不凭常识恢复；原音轨未取得，源完整逐字/听校未通过，非gold。这里所有句子/候选/依据为完整原创，源事实断言不移植。听前2秒、末尾3秒、首遍后1秒和重播提示为本机编排，不当原卷精确时序。合成听辨、目标学生、独立教研、商用和生产未验证。']
    passage='\n\n'.join(body);block=response_markdown(tasks);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists()
    p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+passage+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+'\n\n'.join(teacher)+'\n')
    audit=dict(version=version,id=d['id'],grade='primary5',questions=10,candidate_sha256=ref(p)['sha256'],source_binding=binding['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=passage,body_load_text='',manuscript=ref(manuscript),audio_generation=ref(mp),audio_assets=assets,audio_transcript_in_teacher_only=True,word_phrase_listening=True,source_partial_script_visible=True,load_measure=dict(body_English_words=0,stem_English_words=0,options_English_words_with_repeated_bank=sum(words(v)for q in tasks for _,v in q['options']),output_response_positions=10,audio_dialogue_English_words_once=sum(t['dialogue_words_once']for t in generation['tracks']),audio_spoken_words_with_instructions=sum(t['spoken_words_with_instructions']for t in generation['tracks']),audio_seconds_with_pauses=sum(t['seconds']for t in generation['tracks']),artifact_URLs_excluded_from_reading_load=True),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade=d['grade'],family=d['family'],family_label=d['family_label'],title=d['title'],questions=10,candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],source_form_notice='小五公开期末卷10句辨词/短语、三选、两遍已核；源题面/键和脚本视图在库，原音轨缺且第十脚本截断。完整原创可审阅，非源全输入/独立听校或年龄校准。',format_summary='10句 / 每题3词或短语候选 / 共10回应 / 每句2遍 / 源精确停顿未知')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manuscript',type=Path,action='append',required=True);p.add_argument('--metadata-output',type=Path,required=True);a=p.parse_args();assert not a.metadata_output.exists();rows=[compile_author(m)for m in a.manuscript];a.metadata_output.write_text(json.dumps(rows,ensure_ascii=False,indent=2)+'\n');print(dict(groups=len(rows),responses=10*len(rows)))
