"""Keep agreement, contradiction and absent information distinct in a full sample."""
import hashlib,json,re
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words
LABELS=['TRUE','FALSE','NOT GIVEN']
OPTIONS=[['TRUE','陈述与材料信息一致'],['FALSE','材料给出与陈述矛盾的信息'],['NOT GIVEN','材料既未支持也未反驳该陈述']]

def validate(d,source):
    assert d['source_group_id']==source['id'] and d['grade']==source['level']=='advanced'
    assert d['family']==source['kind']=='reading_information_tristate'
    assert source['features']==dict(materials=1,responses=3,options_each=3,labels=LABELS,outside_knowledge_allowed=False,no_word_limit_or_audio=True)
    assert len(d['paragraphs'])==3 and all(p.strip()for p in d['paragraphs'])
    assert len(d['questions'])==3 and len({q['stem']for q in d['questions']})==3
    text='\n\n'.join(d['paragraphs'])
    for q in d['questions']:
        assert q['answer'] in LABELS and [k for k,_ in q['options']]==LABELS
        assert all(k+'：'in q['rationale']for k in LABELS)
        if q['answer']=='NOT GIVEN':
            assert not q['evidence_quote'] and q['unreported_dimension'] and q['all_paragraphs_checked']==[1,2,3]
        else:
            assert q['evidence_quote'] and q['evidence_quote'] in text and not q.get('unreported_dimension')
            assert q['relation']=='agreement'if q['answer']=='TRUE'else q['relation']=='contradiction'
    assert d['fictional_illustrative_case'] and not d['product_level_equivalence_established']
    return True

def check(group,audit,binding,source):
    texts=[load_ref(r).read_text()for r in source['source_pages']]
    assert 'Marie Curie' in texts[0] and all(k in texts[1]for k in LABELS)
    assert all(k in texts[2]for k in ['1 FALSE','2 NOT GIVEN','3 TRUE'])
    assert source['source_full_input_verified'] and not source['source_original_key_is_gold']
    assert len(source['source_images'])==3 and source['source_pdf_pages']==[12,13,14]
    d=json.loads(load_ref(audit['manuscript']).read_text());validate(d,source)
    assert len(group['questions'])==binding['responses']==3 and all(q['options']==OPTIONS for q in group['questions'])
    assert all(not q.get('unreported_dimension')for q in d['questions']if q['answer']!='NOT GIVEN')
    assert all(q['stem']in group['passageHtml']or q['stem']==t['stem']for q,t in zip(d['questions'],group['questions']))
    assert audit['three_way_information_judgement'] and audit['one_whole_authored_passage'] and audit['outside_knowledge_not_used']
    return True

def compile_author(manuscript,version='0.1'):
    d=json.loads(manuscript.read_text());bp=load_ref(d['source_bindings']);b=next(b for b in json.loads(bp.read_text())['bindings']if b['id']==d['source_binding']);s=next(s for s in json.loads(load_ref(b['source_index']).read_text())['groups']if s['id']==b['source_group_id']);validate(d,s)
    body='### '+d['passage_title']+'\n\n'+'\n\n'.join(d['paragraphs']);qs=[dict(number=n,**{k:q[k]for k in ['stem','options','answer','rationale']})for n,q in enumerate(d['questions'],1)];teacher='虚构的原创学术案例，只以印出材料为信息边界。NOT GIVEN需要检查全文是否支持或反驳；不得把“没有支持”直接当作FALSE，也不引入现实学科常识补答案。\n\n'+d['source_notice'];block=response_markdown(qs);p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+teacher+'\n')
    a=dict(version=version,id=d['id'],grade='advanced',questions=3,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=s['id'],review_response_tasks=qs,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,manuscript=ref(manuscript),three_way_information_judgement=True,one_whole_authored_passage=True,outside_knowledge_not_used=True,relation_review=[{k:v for k,v in q.items()if k not in ['options','rationale']}for q in d['questions']],source_count_increment=0,authored_student_inputs_complete=True,load_measure=dict(body_English_words=words(body),stem_English_words=sum(words(q['stem'])for q in qs),options_English_words_with_repeated_bank=sum(words(v)for q in qs for _,v in q['options']),output_response_positions=3,options_English_words_in_classification_labels=sum(words(k)for q in qs for k,_ in q['options'])),source_level_equivalence_established=False,independent_teacher_student_commercial_production_validated=False);ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n')
    return dict(id=d['id'],grade='advanced',family=d['family'],family_label='阅读信息三态判断',title=d['title'],questions=3,candidate=ref(p),author_check=ref(ap),source_group_ids=[s['id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='1完整材料 / 3陈述 / TRUE、FALSE、NOT GIVEN三态 / 只用材料信息')
