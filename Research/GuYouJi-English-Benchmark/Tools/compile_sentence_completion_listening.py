#!/usr/bin/env python3
"""Bind eight-gap monologue tasks to owned scripts and local audio manifests."""
import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import quote
from grade_mode_evidence import BASE, REPO, load_ref
from quality_review_contract import response_markdown
from render_original_listening import words


def ref(p):
    p=p.resolve()
    return {'path':str(p.relative_to(BASE))if p.is_relative_to(BASE)else str(p.relative_to(REPO)),
            'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}


def check(group,audit,binding,source):
    draft=json.loads(load_ref(audit['manuscript']).read_text())
    generation=json.loads(load_ref(audit['audio_generation']).read_text())
    assert generation['manuscript']==audit['manuscript']
    assert generation['whole_final_audio_decode_passed'] and generation['no_source_recording_reused']
    assert not generation['independent_listening_pronunciation_prosody_student_commercial_production_validated']
    assert draft['source_group_id']==source['id']==binding['source_group_id']
    assert draft['family']==group['kind']=='listening_sentence_completion'
    assert len(draft['clips'])==len(generation['tracks'])==len(audit['audio_assets'])==len(group['requiredAudioAssets'])==1
    clip=draft['clips'][0];track=generation['tracks'][0];asset=audit['audio_assets'][0];shown=group['requiredAudioAssets'][0]
    assert len(clip['turns'])==1 and clip['turns'][0]['speaker']=='N'
    assert len(clip['questions'])==source['responses']==binding['responses']==8
    assert asset['sha256']==track['sha256'] and asset['sha256'] not in {a['sha256']for a in source['original_audio_assets']}
    load_ref(asset)
    assert asset['response_numbers']==track['response_numbers']==shown['response_numbers']==list(range(1,9))
    assert asset['repeat_count']==track['repeat_count']==shown['repeat_count']==2
    assert shown['src']=='../../'+quote(asset['path']) and shown['asset']=={k:asset[k]for k in ['path','sha256']}
    assert abs(asset['seconds']-shown['seconds'])<.01 and track['decoded_frames']>0 and track['peak_abs_sample']>0
    spoken=clip['turns'][0]['text']
    assert spoken in group['reviewText'] and spoken not in group['passageHtml']
    assert audit['audio_transcript_in_teacher_only'] and audit['no_fixed_numeric_word_cap_added']
    for repeat in [1,2]:
        heard=[s for s in track['segments']if s['role']=='dialogue' and s['repeat']==repeat]
        assert [(s['speaker'],s['text'])for s in heard]==[('N',spoken)]
    segments=track['segments'];assert segments[0]['role']=='introduction' and segments[0]['text']==draft['audio_introduction']
    assert segments[1]['role']=='silence' and segments[1]['end_frame']-segments[1]['start_frame']==45*track['sample_rate']
    assert audit['load_measure']['audio_dialogue_English_words_once']==track['dialogue_words_once']==words(spoken)
    assert audit['load_measure']['audio_spoken_words_with_repetition']==track['spoken_words_with_instructions']
    offsets=[]
    for q,record in zip(group['questions'],clip['questions']):
        assert q['stem']==record['stem'] and q['stem'].count('____')==1
        assert q['acceptedAnswers']==record['acceptedAnswers'] and not q['options']
        assert q['fillMarking']['maxWords'] is None and 'minWords' not in q['fillMarking']
        target=q['acceptedAnswers'][0].lower()
        pos=spoken.lower().index(target);offsets.append(pos)
    assert offsets==sorted(offsets), 'Answers must follow the recorded order, not an arbitrary item permutation'
    assert len(set(offsets))==8
    return True


def compile_author(manuscript,manifest_path,output):
    manuscript=manuscript.resolve();manifest_path=manifest_path.resolve();output=output.resolve()
    draft=json.loads(manuscript.read_text());manifest=json.loads(manifest_path.read_text())
    assert manifest['id']==draft['id'] and manifest['manuscript']==ref(manuscript)
    assert manifest['whole_final_audio_decode_passed'] and manifest['no_source_recording_reused']
    assert len(manifest['tracks'])==len(draft['clips'])==1
    clip=draft['clips'][0];track=manifest['tracks'][0]
    assert len(clip['questions'])==8 and len(clip['turns'])==1 and clip['preview_seconds']==45
    bindings_path=BASE/'CompleteCoverage20261017/AdvancedSourceBindings-v0.3.json'
    binding=next(b for b in json.loads(bindings_path.read_text())['bindings']if b['id']=='advancedlistencomplete8')
    assert draft['source_group_id']==binding['source_group_id']
    tasks=[dict(number=n,**q)for n,q in enumerate(clip['questions'],1)]
    assert all(not q['options'] and q['stem'].count('____')==1 for q in tasks)
    audio_path=load_ref(track)
    relative='../../../../'+audio_path.relative_to(REPO).as_posix()
    material=clip['context']+'\n\n[音频1（完整8题；内含两遍，开始前45秒读题）]('+relative+')'
    block=response_markdown(tasks)
    teacher='\n\n'.join('### '+str(q['number'])+'：'+' / '.join(q['acceptedAnswers'])+'\n\n'+q['rationale']for q in tasks)
    teacher+='\n\n### 完整原创独白脚本\n\n'+clip['turns'][0]['text']
    teacher+='\n\n每句1分，共8个回应；按已列词形、拼写和短语变体核对，无任意语义近似评分。原型要求一个词或短语，“通常不超过三词”是说明而不是明文统一上限，本稿不加数字限词。未列形式待复核。音频为本机合成试听，完整独白两遍与45秒读题已绑定；脚本只在解析区显示，非源录音。所有人物、机构和经历为虚构；源原键非独立gold，不由合成音频、结构或程序通过认定C1/产品高级等值、自然语流质量、独立教研、学生、商用或生产通过。\n'
    candidate=output/(draft['id']+'-v0.1.md');ap=output/(draft['id']+'-author-check-v0.1.json')
    assert not candidate.exists() and not ap.exists()
    candidate.write_text('# '+draft['title']+'\n\n## 学生题面\n\n'+draft['instruction']+'\n\n'+material+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher)
    assets=[{k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']}]
    audit=dict(version='0.1',id=draft['id'],grade='advanced',questions=8,candidate_sha256=ref(candidate)['sha256'],source_binding=binding['id'],source_bindings=ref(bindings_path),source_group_id=draft['source_group_id'],review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=material,body_load_text=clip['context'],manuscript=ref(manuscript),audio_generation=ref(manifest_path),audio_assets=assets,audio_transcript_in_teacher_only=True,listening_sentence_completion=True,no_fixed_numeric_word_cap_added=True,author_answer_vector=[q['acceptedAnswers']for q in tasks],load_measure=dict(body_English_words=words(clip['context']),stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=0,output_response_positions=8,audio_dialogue_English_words_once=track['dialogue_words_once'],audio_spoken_words_with_repetition=track['spoken_words_with_instructions'],audio_seconds_with_pauses=track['seconds'],accepted_output_words_range=[sum(min(len(v.split())for v in q['acceptedAnswers'])for q in tasks),sum(max(len(v.split())for v in q['acceptedAnswers'])for q in tasks)],artifact_URLs_excluded_from_reading_load=True),source_count_increment=0,authored_student_inputs_complete=True,source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n')
    return dict(id=draft['id'],grade='advanced',family=draft['family'],family_label=draft['family_label'],title=draft['title'],questions=8,candidate=ref(candidate),author_check=ref(ap),source_group_ids=[draft['source_group_id']],instruction=draft['instruction'],source_form_notice='官方C1 Part2为形式参照：一独白、8句各一空、按录音顺序、听两遍，填一个词或短语，无统一数字词数上限。原创配音为本机合成试听，脚本仅解析可见；非自然听辨或产品高级等值标定。',format_summary='1独白 / 8句各1空 / 词或短语 / 2遍 / 45秒读题 / 不添加统一3词上限')


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--manuscript',type=Path,action='append',required=True);p.add_argument('--audio-dir',type=Path,default=REPO/'build/english-benchmark-authority-20261017/original-audio');p.add_argument('--output',type=Path,default=BASE/'CompleteCoverage20261017/Authored');p.add_argument('--metadata-output',type=Path,required=True);a=p.parse_args();assert not a.metadata_output.exists()
    result=[compile_author(m,a.audio_dir/(json.loads(m.read_text())['id']+'-audio-v0.1.json'),a.output)for m in a.manuscript]
    a.metadata_output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'groups':len(result),'responses':sum(r['questions']for r in result)}))
