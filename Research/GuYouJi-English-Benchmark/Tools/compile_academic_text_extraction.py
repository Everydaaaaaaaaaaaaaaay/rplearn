"""Bounded extraction into six notes, five sentences, or a continuous summary."""
import hashlib,json,re
from itertools import product
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words
MODES={'note_text_completion':(6,1,'six_bullet_notes','笔记抽词补全'),'reading_sentence_completion':(5,1,'five_independent_full_sentences','阅读句子抽词补全'),'summary_text_completion':(5,2,'two_paragraph_continuous_summary','摘要抽词补全')}

def validate(d,s):
    count,limit,layout,label=MODES[d['family']]
    assert d['grade']==s['level']=='advanced' and d['family']==s['kind'] and d['source_group_id']==s['id']
    assert len(d['items'])==s['responses']==count and d['max_words']==s['features']['max_words']==limit
    assert d['layout']==s['features']['response_layout']==layout and d['fictional_illustrative_case']
    assert d['passage'] and d['frame'] and re.findall(r'\((\d+)\) ____',d['frame'])==[str(i)for i in range(1,count+1)]
    assert ('ONE WORD ONLY'if limit==1 else'NO MORE THAN TWO WORDS')in d['instruction']
    if layout=='six_bullet_notes':assert len([line for line in d['frame'].splitlines()if line.startswith('- ')])==6
    if layout=='five_independent_full_sentences':assert len(d['frame'].split('\n\n'))==5 and all(p.endswith('.')for p in d['frame'].split('\n\n'))
    if layout=='two_paragraph_continuous_summary':assert len(d['frame'].split('\n\n'))==2
    for i,item in enumerate(d['items'],1):
        assert item['accepted'] and len(set(v.upper()for v in item['accepted']))==len(item['accepted'])
        assert item['evidence_quote']in d['passage'] and item['rationale'] and item['stem']
        assert all(1<=len(v.split())<=limit for v in item['accepted'])
        assert all(re.search(r'(?<![A-Za-z])'+re.escape(v)+r'(?![A-Za-z])',d['passage'],re.I)for v in item['accepted'])
        assert all(v in item['rejection_reasons']for v in item['rejected']) and not set(item['accepted'])&set(item['rejected'])
    return True

def compile_author(manuscript,version="0.1"):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==d['source_group_id']);validate(d,s);count,limit,layout,label=MODES[d['family']];qs=[]
    for n,item in enumerate(d['items'],1):qs.append(dict(number=n,stem=item['stem'],options=[],acceptedAnswers=item['accepted'],answer=' / '.join(item['accepted']),rationale=item['rationale']+' 排除：'+'；'.join(k+'：'+v for k,v in item['rejection_reasons'].items()),fillMarking=dict(version=1,review='author_context_checked',normalization='source_excerpt_v1',sourceBound=True,unknownSyntax='review',hyphenatedWordCount='one',maxWords=limit,unlisted='review',rejectedAnswers=item['rejected'])))
    filled=[]
    for vector in product(*(i['accepted']for i in d['items'])):
        frame=d['frame']
        for n,v in enumerate(vector,1):frame=frame.replace('('+str(n)+') ____',v)
        assert '____'not in frame;filled.append(dict(answers=list(vector),complete_frame=frame))
    body=d['passage']+'\n\n### '+d['frame_title']+'\n\n'+d['frame'];block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+d['source_notice']+'\n')
    a=dict(version=version,id=d['id'],grade='advanced',questions=count,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,academic_text_extraction=True,full_fill_variant_combinations=len(filled),full_filled_frames=filled,source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(body),passage_English_words=words(d['passage']),frame_English_words=words(d['frame']),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=0,output_response_positions=count),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade='advanced',family=d['family'],family_label=label,title=d['title'],questions=count,candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='1完整材料 / '+str(count)+'空 / 原文摘词无词库 / '+('严格一词'if limit==1 else'最多两词，连字符整体计一词')+' / '+label)

def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,s);assert g['questions']==a['review_response_tasks']
    if d['family']=='note_text_completion':
        assert '<ul class="extraction-notes">' in g['passageHtml'] and g['passageHtml'].count('<li>')==6
        assert all(__import__('html').escape(line[2:]) in g['passageHtml']for line in d['frame'].splitlines())
    assert len(a['full_filled_frames'])==a['full_fill_variant_combinations']==__import__('math').prod(len(i['accepted'])for i in d['items'])
    for row,vector in zip(a['full_filled_frames'],product(*(i['accepted']for i in d['items']))):
        frame=d['frame']
        for n,v in enumerate(vector,1):frame=frame.replace('('+str(n)+') ____',v)
        assert row==dict(answers=list(vector),complete_frame=frame)
    texts=[load_ref(r).read_text()for r in s['source_pages']]
    assert ('ONE WORD ONLY'if d['max_words']==1 else'NO MORE THAN TWO WORDS')in texts[-2]
    assert all(key in texts[-1]for key in s['reference_keys']) and s['source_full_input_verified'] and not s['source_original_key_is_gold']
    return True
