"""Compile the whole form and graph; quantities retain explicit units and axes."""
import hashlib,json,html
from urllib.parse import quote
from itertools import product
from grade_mode_evidence import load_ref,REPO
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words
from academic_form_listening_contract import validate_draft

def draw_box(d,path):
    raw='''<svg xmlns="http://www.w3.org/2000/svg" width="800" height="500" viewBox="0 0 800 500"><defs><marker id="tip" markerWidth="6" markerHeight="6" refX="3" refY="3" orient="auto-start-reverse"><path d="M0 0 L6 3 L0 6" fill="none" stroke="#243f35"/></marker></defs><rect width="800" height="500" fill="white"/><g font-family="Arial,sans-serif" fill="#18392a"><text x="30" y="38" font-size="22">Container dimensions</text><g stroke="#243f35" stroke-width="2" stroke-linejoin="round"><path d="M150 160 L270 90 H570 L450 160 Z" fill="#eef4f0"/><path d="M450 160 L570 90 V270 L450 340 Z" fill="#d9e8df"/><path d="M150 160 H450 V340 H150 Z" fill="#f8fbf9"/><path d="M150 160 H100 M150 340 H100 M150 340 V395 M450 340 V395 M450 340 L470 365 M570 270 L590 295" stroke-width="1"/><g fill="none" marker-start="url(#tip)" marker-end="url(#tip)"><path d="M105 165 V335"/><path d="M155 390 H445"/><path d="M475 361 L585 299"/></g></g><text x="55" y="300" font-size="19" transform="rotate(-90 55 300)">Height: 5 ____</text><text x="223" y="430" font-size="19">Length: LENGTH m</text><text x="550" y="375" font-size="19">Width: 4 ____</text><text x="30" y="475" font-size="16">Complete width and height with units. The length is already given.</text></g></svg>'''.replace('LENGTH',str(d['dimensions']['length_metres']))
    assert not path.exists();path.write_text(raw);return ref(path)

def compile_author(manuscript,manifest):
    d=json.loads(manuscript.read_text());validate_draft(d);gen=json.loads(manifest.read_text());assert gen['manuscript']==ref(manuscript)and gen['whole_final_audio_decode_passed']and gen['no_source_recording_reused'];track=gen['tracks'][0];bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);qs=[]
    for n,q in enumerate(d['clips'][0]['questions'],1):
        protocol={3:'uk_postcode_v1',4:'metric_length_v1',5:'metric_length_v1',8:'sterling_amount_v1'}.get(n,'source_excerpt_v1');c=dict(version=1,review='author_context_checked',normalization=protocol,sourceBound=True,unknownSyntax='review',maxWords=3,unlisted='review',rejectedAnswers=q['rejected'])
        if protocol=='source_excerpt_v1':c['hyphenatedWordCount']='one'
        else:c['numberAllowance']='one'
        if n in [4,5]:c.update(metricMillimetres=d['dimensions']['width_mm'if n==4 else'height_mm'],dimensionAxis='width'if n==4 else'height')
        if n==8:c.update(sterlingPence=d['total_pence'],currencyPrinted='£')
        task=dict(number=n,stem=q['stem'],options=[],acceptedAnswers=q['acceptedAnswers'],answer=' / '.join(q['acceptedAnswers']),rationale=q['rationale']+' 排除：'+'；'.join(k+'：'+v for k,v in q['rejection_reasons'].items()),fillMarking=c)
        if q.get('fillPair'):task['fillPair']=q['fillPair']
        qs.append(task)
    fp=manuscript.parent/(d['id']+'-figure-v0.1.svg');figure=draw_box(d,fp);f=d['form'];form='### '+f['agency']+' — customer quotation form\n\nExample — Country of destination: **'+f['destination']+'**\n\n| Field | Information |\n|---|---|\n| Name | '+f['first_name']+' 1 ____ |\n| Collect from | 2 ____ College, '+f['street']+' |\n| Town | '+f['town']+' |\n| Postcode | 3 ____ |\n\n### Size of container\n\n';after='\n\n| Field | Information |\n|---|---|\n| Contents | clothes; 6 ____; 7 ____ |\n| Total estimated value | £8 ____ |'
    # The "8" is the response number; the currency prefix is fixed, not a digit of the amount.
    after=after.replace('£8 ____','8: £____')
    alt='Three-dimensional rectangular box. The long front bottom edge is the given length; the sloping depth edge is width, response 4; the vertical edge is height, response 5. No missing dimension value is printed.'
    body='[完整原创双人对话（本机一遍，审阅可重播）](../../../../'+track['path']+')\n\n'+form+'!['+alt+']('+str(fp)+')'+after;block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v0.1.md');ap=manuscript.parent/(d['id']+'-author-check-v0.1.json');assert not p.exists()and not ap.exists();teacher='\n\n'.join(t['speaker']+': '+t['text']for t in d['clips'][0]['turns'])+'\n\n'+d['source_notice'];p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
    baseline=[q['acceptedAnswers'][0]for q in qs];pair=qs[5]['fillPair'];baseline[6]=pair['members'][1]['forms'][0];vectors=[]
    for n,q in enumerate(qs):
        for answer in q['acceptedAnswers']:
            v=baseline[:];v[n]=answer
            if n in [5,6]:
                member=next(i for i,m in enumerate(pair['members'])if answer in m['forms']);v[6 if n==5 else 5]=pair['members'][1-member]['forms'][0]
            if v not in vectors:vectors.append(v)
    a=dict(version='0.1',id=d['id'],grade='advanced',questions=8,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=b['source_group_id'],manuscript=ref(manuscript),audio_generation=ref(manifest),audio_assets=[{k:track[k]for k in ['path','sha256','seconds','response_numbers','repeat_count','mime_type']}],audio_transcript_in_teacher_only=True,academic_form_listening=True,review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text=form+after,figure_asset=figure,figure_English_words=words('Container dimensions Height Width Length Complete width and height with units The length is already given'),image_alt_English_words=words(alt),source_count_increment=0,authored_student_inputs_complete=True,whole_answer_vectors=vectors,whole_vector_scope='all_individual_accepted_forms_pair_referent_preserved_not_full_crossproduct',load_measure=dict(body_English_words=words(form+after),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=0,output_instruction_English_words=words(d['instruction']),output_response_positions=8,audio_dialogue_English_words_once=track['dialogue_words_once'],audio_spoken_words_with_instructions=track['spoken_words_with_instructions'],audio_seconds_with_pauses=track['seconds']),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade='advanced',family=d['family'],family_label='听力表单补全',title=d['title'],questions=8,candidate=ref(p),author_check=ref(ap),source_group_ids=[b['source_group_id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary=d['format_summary'])

def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate_draft(d);gen=json.loads(load_ref(a['audio_generation']).read_text());t=gen['tracks'][0];assert gen['manuscript']==a['manuscript']and gen['whole_final_audio_decode_passed']and gen['no_source_recording_reused']
    assert len(g['requiredAudioAssets'])==len(g['requiredPassageImages'])==1 and g['requiredAudioAssets'][0]['asset']=={k:t[k]for k in ['path','sha256']}
    assert t['response_numbers']==list(range(1,9))and t['repeat_count']==1 and g['questions']==a['review_response_tasks']
    assert all(x['text']in g['reviewText']and x['text']not in g['passageHtml']for x in d['clips'][0]['turns'])
    assert s['source_full_printed_input_and_script_verified']and s['necessary_box_dimension_diagram']and not s['source_original_key_is_gold']
    assert s['features']['max_words']==3 and s['features']['unordered_answer_pair']==[6,7]
    assert g['questions'][5]['fillPair']==g['questions'][6]['fillPair']
    assert g['questions'][3]['fillMarking']['metricMillimetres']==d['dimensions']['width_mm']and g['questions'][4]['fillMarking']['metricMillimetres']==d['dimensions']['height_mm']
    assert g['questions'][7]['fillMarking']['sterlingPence']==d['total_pence']
    return True
