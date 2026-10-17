"""Complete source-extracted tables and branching flow charts, with exact variants."""
import hashlib,html,json,re
from itertools import product
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words

def validate(d,s):
    assert d['grade']==s['level']=='advanced' and d['family']==s['kind']
    n=5 if d['family']=='table_completion' else 3
    assert d['source_group_id']==s['id'] and len(d['items'])==s['responses']==n
    assert s['features']['max_words']==d['max_words']==(3 if n==5 else 2)
    assert d['fictional_illustrative_case'] and not d['product_level_equivalence_established']
    assert d['passage'] and d['instruction'] and d['diagram_title']
    for i,item in enumerate(d['items'],1):
        assert item['accepted'] and len(set(v.upper()for v in item['accepted']))==len(item['accepted'])
        assert item['evidence_quote'] in d['passage'] and item['rationale']
        assert all(len(v.split())<=d['max_words']for v in item['accepted'])
        assert all(re.search(r'(?<![A-Za-z])'+re.escape(v)+r'(?![A-Za-z])',d['passage'],re.I) for v in item['accepted'])
        assert not set(item['accepted'])&set(item['rejected']) and item['rejection_reasons'] and all(v in item['rejection_reasons']for v in item['rejected'])
    if n==5:
        assert len(d['table_headers'])==6 and len(d['table_rows'])==3 and all(len(r)==6 for r in d['table_rows'])
        assert [[j for j,c in enumerate(r)if re.fullmatch(r'\([1-5]\) ____',c)]for r in d['table_rows']]==[[],[2,4,5],[2,3]]
        frame='\n'.join(' | '.join(r)for r in [d['table_headers']]+d['table_rows'])
    else:
        assert d['topology']=='single_trunk_two_alternative_explanations'
        assert len(d['trunk'])==3 and len(d['branches'])==2 and all(len(b)==2 for b in d['branches'])
        frame='\n'.join(d['trunk']+[x for b in d['branches']for x in b])
    assert sorted(re.findall(r'\(([1-5])\) ____',frame))==[str(i)for i in range(1,n+1)]
    return frame

def diagram(d,path):
    esc=html.escape
    out=['<svg xmlns="http://www.w3.org/2000/svg" width="1080" height="460" viewBox="0 0 1080 460">','<rect width="1080" height="460" fill="#fff"/>','<g fill="#172435" font-family="Arial,sans-serif" font-size="18">',f'<text x="540" y="35" text-anchor="middle" font-size="23">{esc(d["diagram_title"])}</text>']
    def lines(text,x,y,width=22):
        import textwrap
        for j,line in enumerate(textwrap.wrap(text,width=width,break_long_words=False)):
            out.append(f'<text x="{x}" y="{y+j*25}" text-anchor="middle">{esc(line)}</text>')
    if d['family']=='table_completion':
        xs=[15,175,285,465,670,860,1065];ys=[65,175,260,345,445]
        for x in xs:out.append(f'<path d="M{x} 65 V445" stroke="#748194" fill="none"/>')
        for y in ys:out.append(f'<path d="M15 {y} H1065" stroke="#748194" fill="none"/>')
        for row,r in enumerate([d['table_headers']]+d['table_rows']):
            for col,text in enumerate(r):lines(text,(xs[col]+xs[col+1])/2,ys[row]+31,14 if col in [0,2,3,4,5] else 8)
    else:
        out.append('</g><defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto"><path d="M0,0 L0,6 L9,3 z" fill="#536278"/></marker></defs><g fill="#172435" font-family="Arial,sans-serif" font-size="19">')
        for k,text in enumerate(d['trunk']):
            y=55+k*70;out.append(f'<rect x="270" y="{y}" width="540" height="45" rx="5" fill="#eef3f8" stroke="#748194"/>');lines(text,540,y+29,48)
            if k<2:out.append(f'<path d="M540 {y+45} V{y+68}" stroke="#536278" marker-end="url(#arrow)"/>')
        for x in [265,815]:out.append(f'<path d="M540 240 L{x} 285" stroke="#536278" marker-end="url(#arrow)"/>')
        for x,b in zip([265,815],d['branches']):
            out.append(f'<rect x="{x-245}" y="290" width="490" height="145" rx="5" fill="#eef3f8" stroke="#748194"/>');lines(b[0],x,320,40);lines(b[1],x,358,42)
    out.append('</g></svg>');assert not path.exists();path.write_text(''.join(out));return ref(path)

def compile_author(manuscript,version="0.1"):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==d['source_group_id']);frame=validate(d,s)
    fp=load_ref(d['reuse_figure']) if d.get('reuse_figure') else manuscript.parent/(d['id']+'-figure-v'+version+'.svg');fig=d['reuse_figure'] if d.get('reuse_figure') else diagram(d,fp);qs=[]
    for n,item in enumerate(d['items'],1):
        qs.append(dict(number=n,stem=item['stem'],options=[],acceptedAnswers=item['accepted'],answer=' / '.join(item['accepted']),rationale=item['rationale']+' 排除：'+'；'.join(k+'：'+v for k,v in item['rejection_reasons'].items()),fillMarking=dict(version=1,review='author_context_checked',normalization='source_excerpt_v1',sourceBound=True,unknownSyntax='review',hyphenatedWordCount='one',maxWords=d['max_words'],unlisted='review',rejectedAnswers=item['rejected'])))
    body=d['passage']+'\n\n!['+d['diagram_alt']+']('+str(fp)+')';block=response_markdown(qs)
    filled=[]
    for vector in product(*(q['acceptedAnswers']for q in qs)):
        full=frame
        for n,value in enumerate(vector,1):full=full.replace('('+str(n)+') ____',value)
        assert '____'not in full;filled.append(dict(answers=list(vector),complete_layout=full))
    p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+d['source_notice']+'\n')
    a=dict(version=version,id=d['id'],grade='advanced',questions=len(qs),candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,academic_extracted_completion=True,figure_asset=fig,full_fill_variant_combinations=len(filled),full_filled_layouts=filled,unfilled_layout_frame=frame,source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(body),passage_English_words=words(d['passage']),diagram_English_words=words(frame+' '+d['diagram_title']),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=0,output_response_positions=len(qs)),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade='advanced',family=d['family'],family_label='表格抽词补全'if len(qs)==5 else'流程图抽词补全',title=d['title'],questions=len(qs),candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='1完整材料 / '+str(len(qs))+'空 / 无词库 / 摘取原文 / 最多'+str(d['max_words'])+'词 / '+('三行六列表格'if len(qs)==5 else'主干后两种解释分支'))

def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());frame=validate(d,s)
    assert g['questions']==a['review_response_tasks'] and len(g['requiredPassageImages'])==1
    assert len(a['full_filled_layouts'])==a['full_fill_variant_combinations']==__import__('math').prod(len(i['accepted'])for i in d['items'])
    for row,vector in zip(a['full_filled_layouts'],product(*(i['accepted']for i in d['items']))):
        f=frame
        for n,v in enumerate(vector,1):f=f.replace('('+str(n)+') ____',v)
        assert row==dict(answers=list(vector),complete_layout=f)
    texts=[load_ref(r).read_text()for r in s['source_pages']]
    assert s['source_full_input_verified'] and not s['source_original_key_is_gold']
    assert 'NO MORE THAN '+('THREE'if len(d['items'])==5 else'TWO')+' WORDS'in texts[1]
    assert a['academic_extracted_completion'] and a['authored_student_inputs_complete']
    for q,item in zip(g['questions'],d['items']):
        assert q['acceptedAnswers']==item['accepted'] and q['fillMarking']['maxWords']==d['max_words']
    return True
