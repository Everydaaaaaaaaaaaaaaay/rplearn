"""Compile full owned recordings and spatial/closed/extracted response inputs."""
import hashlib,json,html,re
from itertools import product
from urllib.parse import quote
from grade_mode_evidence import load_ref,REPO
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words
from academic_bundle_listening_contract import validate_draft,ROLES

def draw_plan(d,path):
    fixed=d['fixed_labels'];escape=html.escape
    def text(x,y,value,size=16,extra=''):
        return '<text x="'+str(x)+'" y="'+str(y)+'" font-size="'+str(size)+'" '+extra+'>'+escape(value)+'</text>'
    raw='<svg xmlns="http://www.w3.org/2000/svg" width="820" height="680" viewBox="0 0 820 680"><rect width="820" height="680" fill="#fff"/>'
    raw+='<g font-family="Arial,sans-serif" fill="#182c29">'+text(35,32,d['plan_title'],22)
    # Every room boundary is explicit; gaps in internal walls are doorways.
    raw+='<g fill="none" stroke="#263c35" stroke-width="2.5"><path d="M60 70 H510 V570 H230 M180 570 H60 V70 M220 70 V200 M390 70 V270 M390 310 V570 M60 200 H90 M130 200 H280 M320 200 H390 M60 360 H180 V470 M180 510 V570 M230 360 H510 M230 360 V450 M230 490 V570 M230 520 H390"/>'
    raw+='<path d="M90 200 V160 M280 200 V160 M390 270 H430 M180 510 H140 M230 450 H270" stroke-width="1.6"/>'
    raw+='<rect x="239" y="531" width="142" height="26" fill="#edf3ef"/></g>'
    raw+=text(75,120,fixed['upper_left'],15)+text(249,550,fixed['desk'],13)+text(402,458,fixed['office'],13)
    raw+=text(190,288,fixed['main'],17)+text(78,338,fixed['left_shelves'],13,'transform="rotate(-90 78 338)"')+text(375,230,fixed['right_shelves'],13,'transform="rotate(90 375 230)"')
    for n,(x,y)in enumerate([(82,432),(266,414),(195,226),(255,120),(415,210)],1):raw+=text(x,y,str(n)+' ____',19,'font-weight="bold"')
    raw+='<path d="M205 625 V585 M198 594 L205 585 L212 594" stroke="#182c29" stroke-width="3" fill="none"/>'+text(165,652,'Entrance',16)
    raw+='<rect x="545" y="75" width="253" height="490" fill="#f5f8f5" stroke="#587265"/>'+text(560,105,'Choose A–I',17,'font-weight="bold"')
    for n,(k,v)in enumerate(d['candidates']):
        parts=v.split(' ');lines=[];line=''
        for word in parts:
            if len(line+' '+word)>23:lines.append(line);line=word
            else:line=(line+' '+word).strip()
        lines.append(line);y=143+n*45
        for j,line in enumerate(lines):raw+=text(561,y+j*17,(k+'. 'if j==0 else'    ')+line,15)
    raw+='</g></svg>';assert not path.exists();path.write_text(raw);return ref(path)

def compile_author(manuscript,manifest):
    d=json.loads(manuscript.read_text());validate_draft(d);gen=json.loads(manifest.read_text());assert gen['manuscript']==ref(manuscript) and gen['whole_final_audio_decode_passed'] and gen['no_source_recording_reused']
    bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==d['source_group_id']);kind=d['family'];c=d['clips'][0];track=gen['tracks'][0];audio=load_ref(track);qs=[]
    for n,q in enumerate(c['questions'],1):
        if q['options']:
            task=dict(number=n,stem=q['stem'],options=q['options'],answer=q['answer'],rationale=q['rationale']+'；'+'；'.join(k+'：'+v for k,v in q['candidate_reasons'].items()))
        else:
            task=dict(number=n,stem=q['stem'],options=[],acceptedAnswers=q['acceptedAnswers'],answer=' / '.join(q['acceptedAnswers']),rationale=q['rationale']+' 排除：'+'；'.join(k+'：'+v for k,v in q['rejection_reasons'].items()),fillMarking=dict(version=1,review='author_context_checked',normalization='source_excerpt_v1',sourceBound=True,unknownSyntax='review',hyphenatedWordCount='one',maxWords=2,unlisted='review',rejectedAnswers=q['rejected']))
        qs.append(task)
    body='[完整原创材料（本机一遍，审阅可重播）](../../../../'+str(audio.relative_to(REPO))+')';body_load='';extra={}
    if kind=='listening_plan_label_matching':
        fp=manuscript.parent/(d['id']+'-figure-v0.1.svg');fig=draw_plan(d,fp);body+='\n\n!['+d['plan_alt']+']('+str(fp)+')';extra=dict(figure_asset=fig,spatial_roles=ROLES)
        body_load='\n'.join(v for k,v in d['candidates']);extra.update(figure_English_words=words(d['plan_title']+' '+' '.join(d['fixed_labels'].values())+' Entrance Choose'),image_alt_English_words=words(d['plan_alt']))
    if kind=='listening_dialogue_sentence_completion':extra['whole_answer_vectors']=[list(v)for v in product(*(q['acceptedAnswers']for q in qs))]
    teacher='\n\n'.join(t['speaker']+': '+t['text']for t in c['turns'])+'\n\n'+d['source_notice'];block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v0.1.md');ap=manuscript.parent/(d['id']+'-author-check-v0.1.json');assert not p.exists()and not ap.exists()
    p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
    a=dict(version='0.1',id=d['id'],grade='advanced',questions=len(qs),candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),audio_generation=ref(manifest),audio_assets=[{k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']}],audio_transcript_in_teacher_only=True,academic_bundle_listening=True,review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text=body_load,source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(body_load),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=sum(words(v)for q in qs for k,v in q['options']),output_instruction_English_words=words(d['instruction']),output_response_positions=len(qs),audio_dialogue_English_words_once=track['dialogue_words_once'],audio_spoken_words_with_instructions=track['spoken_words_with_instructions'],audio_seconds_with_pauses=track['seconds']),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False,**extra);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    m=dict(id=d['id'],grade='advanced',family=kind,family_label=d['family_label'],title=d['title'],questions=len(qs),candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary=d['format_summary'])
    if kind=='listening_plan_label_matching':m['use_select_controls']=True
    return m

def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate_draft(d);gen=json.loads(load_ref(a['audio_generation']).read_text());track=gen['tracks'][0]
    assert gen['manuscript']==a['manuscript'] and gen['whole_final_audio_decode_passed'] and gen['no_source_recording_reused']
    assert s['source_full_printed_input_and_script_verified'] and not s['source_original_key_is_gold']
    assert len(g['requiredAudioAssets'])==1 and g['requiredAudioAssets'][0]['asset']=={k:track[k]for k in ['path','sha256']}
    assert g['requiredAudioAssets'][0]['src']=='../../'+quote(track['path'])
    assert track['response_numbers']==list(range(1,b['responses']+1)) and track['repeat_count']==1
    assert [(t['speaker'],t['text'])for t in track['segments']if t['role']=='dialogue']==[(t['speaker'],t['text'])for t in d['clips'][0]['turns']]
    assert all(t['text']in g['reviewText']and t['text']not in g['passageHtml']for t in d['clips'][0]['turns'])
    assert g['questions']==a['review_response_tasks']
    native=next(r for r in json.loads(load_ref(s['source_native_index']).read_text())if r['path']==s['source_native_record_path']);assert len(native['pages'])==len(s['source_pdf_pages'])
    if d['family']=='listening_plan_label_matching':
        assert g['fixedSharedBank'] and len(g['requiredPassageImages'])==1 and s['printed_no_recording_note_verified']
        assert 'There is no Listening recording for this tapescript' in native['pages'][1]['text']
        assert a['spatial_roles']==ROLES and s['reference_keys']==list('HGDBF')
    elif d['family']=='listening_dialogue_sentence_completion':
        assert s['features']['max_words']==2 and len(g['questions'])==4
        assert a['whole_answer_vectors']==[list(v)for v in product(*(q['acceptedAnswers']for q in g['questions']))]
    else:assert len(g['questions'])==2 and s['reference_keys']==list('CA')
    return True
