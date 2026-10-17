"""Continuous four-gap bank summaries and complete five-label authored diagrams."""
import hashlib,html,json,re
from itertools import product
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words

def validate(d,s):
    assert d['grade']==s['level']=='advanced' and d['family']==s['kind'] and d['source_group_id']==s['id'] and d['fictional_illustrative_case']
    bank=d['family']=='summary_bank_completion';count=4 if bank else 5
    assert len(d['items'])==s['responses']==count and d['passage']
    if bank:
        assert [k for k,v in d['candidates']]==list('ABCDEFG') and len({v for k,v in d['candidates']})==7
        assert re.findall(r'\((\d+)\) ____',d['frame'])==list('1234')
        assert d['reuse_rule']==s['features']['reuse_rule']=='not_explicit_in_sample'
        assert '不额外规定' in d['instruction']
        for i in d['items']:assert i['answer'] in list('ABCDEFG') and set(i['candidate_reasons'])==set('ABCDEFG') and all(i['candidate_reasons'].values()) and i['evidence_quote']in d['passage']
    else:
        assert d['max_words']==s['features']['max_words']==3 and s['features']['necessary_diagram']
        assert d['authored_layout_not_source_machine_replica'] and len(d['spatial_roles'])==5
        assert d['spatial_roles']==['incoming_material','material_on_work_surface','overhead_reference','right_hand_device','output_for_named_purpose']
        for i in d['items']:
            assert i['accepted'] and i['evidence_quote']in d['passage'] and i['rationale']
            assert all(1<=len(v.split())<=3 for v in i['accepted'])
            for v in i['accepted']:
                base=re.sub(r'^(?:a|the) ','',v)
                assert re.search(r'(?<![A-Za-z])'+re.escape(v)+r'(?![A-Za-z])',d['passage'],re.I)or base in i.get('optional_article_bases',[]) and base in d['passage']
            assert not set(i['accepted'])&set(i['rejected']) and all(v in i['rejection_reasons']for v in i['rejected'])
    return True

def diagram(d,path):
    e=html.escape;out=['<svg xmlns="http://www.w3.org/2000/svg" width="900" height="520" viewBox="0 0 900 520">','<rect width="900" height="520" fill="#fff"/>','<defs><marker id="arrow" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto"><path d="M0,0 L0,6 L9,3 z" fill="#40556b"/></marker></defs>','<g font-family="Arial,sans-serif" font-size="23" fill="#1c3041">',f'<text x="450" y="35" text-anchor="middle">{e(d["diagram_title"])}</text>','<rect x="210" y="205" width="435" height="125" fill="#eff4f7" stroke="#738698"/>','<path d="M200 340 H750 M245 340 V440 M700 340 V440" fill="none" stroke="#738698" stroke-width="5"/>','<rect x="140" y="240" width="90" height="80" fill="#e2eaf0" stroke="#738698"/>','<text x="185" y="355" text-anchor="middle" font-size="19">entry tray</text>','<rect x="290" y="120" width="300" height="22" fill="#e2eaf0" stroke="#738698"/>','<path d="M400 260 H535 M400 275 H545 M400 290 H525" stroke="#738698" stroke-width="5"/>','<rect x="650" y="220" width="90" height="110" fill="#e2eaf0" stroke="#738698"/>','<circle cx="695" cy="270" r="21" fill="#fff" stroke="#738698"/>','<rect x="740" y="390" width="130" height="55" fill="#e2eaf0" stroke="#738698"/>','<path d="M60 270 H135" stroke="#40556b" fill="none" stroke-width="2" marker-end="url(#arrow)"/><path d="M235 270 H285" stroke="#40556b" fill="none" stroke-width="2" marker-end="url(#arrow)"/><path d="M550 275 H640" stroke="#40556b" fill="none" stroke-width="2" marker-end="url(#arrow)"/><path d="M740 310 H805 V380" stroke="#40556b" fill="none" stroke-width="2" marker-end="url(#arrow)"/>','<text x="95" y="230" text-anchor="middle">(1) ____</text>','<text x="455" y="240" text-anchor="middle">(2) ____</text>','<text x="450" y="395" text-anchor="middle" font-size="19">work surface</text>','<text x="300" y="85">(3) ____</text>','<path d="M390 90 L435 115" stroke="#40556b" fill="none" marker-end="url(#arrow)"/>','<text x="750" y="160">(4) ____</text>','<path d="M770 170 L710 215" stroke="#40556b" fill="none" marker-end="url(#arrow)"/>','<text x="805" y="480" text-anchor="middle">(5) ____</text>',f'<text x="805" y="508" text-anchor="middle" font-size="19">for {e(d["output_purpose"])}</text>','</g></svg>'];assert not path.exists();path.write_text(''.join(out));return ref(path)

def compile_author(manuscript,version="0.1"):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==d['source_group_id']);validate(d,s);bank=d['family']=='summary_bank_completion';qs=[];body=d['passage'];extra={}
    if bank:
        body+='\n\n### Summary\n\n'+d['frame']+'\n\n### Shared Words\n\n'+'\n\n'.join(k+'. '+v for k,v in d['candidates'])
        for n,i in enumerate(d['items'],1):qs.append(dict(number=n,stem='摘要第'+str(n)+'空',options=d['candidates'],answer=i['answer'],rationale='；'.join(k+'：'+i['candidate_reasons'][k]for k,v in d['candidates'])))
        full=d['frame']
        for n,i in enumerate(d['items'],1):full=full.replace('('+str(n)+') ____',dict(d['candidates'])[i['answer']])
        extra.update(full_filled_summary=full,unique_candidate_judgements=[dict(number=n,candidate=k,is_best=k==i['answer'],reason=i['candidate_reasons'][k])for n,i in enumerate(d['items'],1)for k,v in d['candidates']],source_reuse_rule='not_explicit_in_sample')
    else:
        fp=manuscript.parent/(d['id']+'-figure-v'+version+'.svg');fig=diagram(d,fp);body+='\n\n!['+d['diagram_alt']+']('+str(fp)+')'
        for n,i in enumerate(d['items'],1):qs.append(dict(number=n,stem='图示第'+str(n)+'处',options=[],acceptedAnswers=i['accepted'],answer=' / '.join(i['accepted']),rationale=i['rationale']+' 排除：'+'；'.join(k+'：'+v for k,v in i['rejection_reasons'].items()),fillMarking=dict(version=1,review='author_context_checked',normalization='source_excerpt_v1',sourceBound=True,unknownSyntax='review',hyphenatedWordCount='one',maxWords=3,unlisted='review',rejectedAnswers=i['rejected'])))
        extra.update(figure_asset=fig,spatial_roles=d['spatial_roles'],full_label_vectors=[list(v)for v in product(*(i['accepted']for i in d['items']))],full_fill_variant_combinations=__import__('math').prod(len(i['accepted'])for i in d['items']))
    block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+d['source_notice']+'\n');a=dict(version=version,id=d['id'],grade='advanced',questions=len(qs),candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],manuscript=ref(manuscript),review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,academic_summary_or_diagram=True,source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(body),passage_English_words=words(d['passage']),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=sum(words(v)for q in qs for k,v in q['options']),output_response_positions=len(qs)),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False,**extra);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n');m=dict(id=d['id'],grade='advanced',family=d['family'],family_label='摘要共享词库补全'if bank else'示意图标注抽词',title=d['title'],questions=len(qs),candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='1材料 / 连续摘要4空 / A—G七共享词项 / 填字母 / 源复用未印'if bank else'1材料 / 完整原创布置图 / 5空间标注 / 原文词语最多3词 / 输出用途已印')
    if bank:m['use_select_controls']=True
    return m

def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());validate(d,s);assert g['questions']==a['review_response_tasks'];texts=[load_ref(r).read_text()for r in s['source_pages']]
    if d['family']=='summary_bank_completion':
        assert g['fixedSharedBank'] and len(a['unique_candidate_judgements'])==28 and s['reference_keys']==list('EGBF')
        full=d['frame']
        for n,i in enumerate(d['items'],1):full=full.replace('('+str(n)+') ____',dict(d['candidates'])[i['answer']])
        assert a['full_filled_summary']==full and '____'not in full
    else:
        assert load_ref(a['figure_asset']).read_text().count('marker-end=')==6
        assert len(g['requiredPassageImages'])==1 and a['spatial_roles']==d['spatial_roles'] and 'NO MORE THAN THREE WORDS'in texts[1]
        assert a['full_label_vectors']==[list(v)for v in product(*(i['accepted']for i in d['items']))]
        assert len(a['full_label_vectors'])==a['full_fill_variant_combinations']
    return True
