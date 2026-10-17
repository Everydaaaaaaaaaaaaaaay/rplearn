"""A complete illustrated four-product grid and its three source-bound questions."""
import hashlib,html,json,re
import xml.etree.ElementTree as ET
from grade_mode_evidence import load_ref
from quality_review_contract import response_markdown
from compile_short_dialogue_listening import ref
from render_original_listening import words


def coloured_item(colour,name,capitalized=False):
    # These source-bound charts use the finite colour vocabulary below.
    assert colour in {'blue','red','black','green','white','yellow','orange','brown'}
    article='an' if colour=='orange' else 'a'
    return (article.capitalize() if capitalized else article)+' '+colour+' '+name


def validate(d):
    assert d['shop_grid_reading'] and d['grade']==7 and d['family']=='reading_choice'
    assert d['source_group_id']=='grade7-huangshan2026-21cnjy25150014.reading.A'
    assert d['fictional_shops'] and len(d['items'])==4 and len(d['questions'])==3
    assert [i['offer']for i in d['items']]==['day_discount','day_discount','two_for','free_gift']
    assert len(set(i['name']for i in d['items']))==4
    assert d['items'][0]['store']==d['items'][1]['store']!=d['items'][2]['store']==d['items'][3]['store']
    for item in d['items']:
        assert len(item['colours'])==2 and len(set(item['colours']))==2 and item['price']>0
        if item['offer']=='day_discount':assert 0<item['special_price']<item['price']
        if item['offer']=='two_for':assert 0<item['bundle_price']<2*item['price']
        if item['offer']=='free_gift':assert item['gift']
    computed=[]
    for n,q in enumerate(d['questions'],1):
        assert q['number']==n and [k for k,v in q['options']]==list('ABCD')
        assert len({v.casefold()for k,v in q['options']})==4 and q['answer'] in list('ABCD')
        assert set(q['candidate_reasons'])==set('ABCD') and all(q['candidate_reasons'].values())
        if n==1:
            assert q['kind']=='gift' and q['item_index']==3
            assert q['stem']=='What can you get for free if you buy a '+d['items'][3]['name']+'?'
            truth={k:v==d['items'][3]['gift']for k,v in q['option_gifts'].items()}
            assert q['options']==[[k,('An 'if v[0]in'aeiou'else'A ')+v+'.']for k,v in q['option_gifts'].items()]
        elif n==2:
            i=d['items'][2];assert q['kind']=='saving' and q['item_index']==2
            assert q['stem']=='How much do you save by buying two '+i['plural']+' at '+i['store']+'?'
            truth={k:v==2*i['price']-i['bundle_price']for k,v in q['option_amounts'].items()}
            assert q['options']==[[k,'¥'+str(v)]for k,v in q['option_amounts'].items()]
        else:
            assert q['kind']=='store_colour_pair' and q['store']==d['items'][0]['store']
            assert q['stem']=='Which pair can you buy at '+q['store']+'?'
            truth={};labels=[]
            for k,pair in q['option_pairs'].items():
                assert len(pair)==2 and [z[0]for z in pair]in[[0,1],[2,3]]
                truth[k]=all(d['items'][i]['store']==q['store'] and colour in d['items'][i]['colours']for i,colour in pair)
                labels.append([k,coloured_item(pair[0][1],d['items'][pair[0][0]]['name'],True)+' and '+coloured_item(pair[1][1],d['items'][pair[1][0]]['name'])+'.'])
            assert q['options']==labels
        assert set(truth)==set('ABCD') and [k for k,v in truth.items()if v]==[q['answer']]
        computed.append(truth)
    return computed


def icon(kind,colour):
    fill=html.escape(colour)
    shapes={
      'book':'<rect x="45" y="28" width="134" height="172" rx="7"/><path d="M72 29V199M90 64H157M90 90H157M90 116H143" fill="none"/>',
      'case':'<rect x="24" y="67" width="176" height="95" rx="20"/><path d="M25 94H199M154 94V113M156 113H172" fill="none"/>',
      'ruler':'<rect x="18" y="79" width="188" height="62" rx="3"/><path d="M40 80V114M62 80V102M84 80V114M106 80V102M128 80V114M150 80V102M172 80V114M194 80V102" fill="none"/>',
      'bag':'<path d="M72 67V51Q112 15 152 51V67" fill="none"/><rect x="49" y="62" width="126" height="142" rx="20"/><rect x="71" y="119" width="82" height="58" rx="9" fill="none"/>',
      'shirt':'<path d="M75 39L92 49H132L149 39L194 68L170 107L152 94V190H72V94L54 107L30 68Z"/><path d="M92 49Q112 74 132 49" fill="none"/>',
      'cap':'<path d="M50 121V102Q50 38 117 38Q176 38 176 121Z"/><path d="M50 121Q120 99 176 121L204 144Q119 172 25 145Z"/>',
      'ball':'<circle cx="112" cy="116" r="81"/><path d="M46 69Q105 107 177 162M179 70Q107 106 45 163M112 35Q74 114 112 197M112 35Q149 116 112 197" fill="none"/>',
      'lunchbox':'<rect x="25" y="60" width="174" height="125" rx="22"/><path d="M25 97H199M78 60V40H146V60" fill="none"/><rect x="88" y="91" width="48" height="23" fill="white"/>',
      'cup':'<path d="M57 47H155V162Q106 202 57 162Z"/><path d="M155 67Q211 65 194 113Q183 137 155 130" fill="none"/>',
      'spoon':'<ellipse cx="112" cy="60" rx="40" ry="50"/><path d="M101 109V202H123V109"/>',
      'basket':'<path d="M31 94H193L172 198H52Z"/><path d="M62 94Q62 13 112 13Q162 13 162 94M69 112L78 194M110 109V195M153 112L146 194" fill="none"/>',
    }
    return '<g fill="'+fill+'" stroke="#30404b" stroke-width="5" stroke-linejoin="round">'+shapes[kind]+'</g>'


def figure(d,path):
    palette={'blue':'#82b8d7','red':'#e59691','black':'#777d83','green':'#91bd8a','white':'#fafafa','yellow':'#ead17f','orange':'#e6ae77','brown':'#b99779'}
    esc=html.escape;out=['<svg xmlns="http://www.w3.org/2000/svg" width="920" height="820" viewBox="0 0 920 820"><rect width="920" height="820" fill="white"/><g font-family="Arial,sans-serif" fill="#203833">',f'<text x="30" y="40" font-size="26" font-weight="bold">{esc(d["chart_title"])}</text>','<text x="30" y="70" font-size="19">Prices are in yuan.</text>']
    for n,i in enumerate(d['items']):
        x=30+440*(n%2);y=95+345*(n//2)
        out+=[f'<rect x="{x}" y="{y}" width="410" height="320" rx="5" fill="#f6f9f7" stroke="#526d60"/>',f'<text x="{x+18}" y="{y+35}" font-size="23" font-weight="bold">{esc(i["name"].capitalize())}</text>',f'<g transform="translate({x+295} {y+48}) scale(.3)">'+icon(i['icon'],palette[i['colours'][0]])+'</g>',f'<text x="{x+18}" y="{y+145}" font-size="20">Colours: {esc(" / ".join(i["colours"]))}</text>',f'<text x="{x+18}" y="{y+185}" font-size="20">Price: ¥{i["price"]}</text>']
        extra=('¥'+str(i['special_price'])+' on '+d['sale_day'] if i['offer']=='day_discount' else 'Buy two for ¥'+str(i['bundle_price']) if i['offer']=='two_for' else 'Free gift: '+('an 'if i['gift'][0]in'aeiou'else'a ')+i['gift'])
        out+=[f'<text x="{x+18}" y="{y+225}" font-size="19">{esc(extra)}</text>',f'<text x="{x+18}" y="{y+280}" font-size="21">Where: {esc(i["store"])}</text>']
    out.append('</g></svg>');assert not path.exists();path.write_text(''.join(out));return ref(path)


def validate_figure_text(d,raw):
    """Match each card in order, so swapped prices cannot pass a global word check."""
    values=[''.join(n.itertext())for n in ET.fromstring(raw).iter()if n.tag.split('}')[-1]=='text']
    expected=[d['chart_title'],'Prices are in yuan.']
    for i in d['items']:
        extra=('¥'+str(i['special_price'])+' on '+d['sale_day'] if i['offer']=='day_discount' else 'Buy two for ¥'+str(i['bundle_price']) if i['offer']=='two_for' else 'Free gift: '+('an 'if i['gift'][0]in'aeiou'else'a ')+i['gift'])
        expected += [i['name'].capitalize(),'Colours: '+' / '.join(i['colours']),'Price: ¥'+str(i['price']),extra,'Where: '+i['store']]
    assert values==expected, 'Printed chart and bound item facts differ'
    return '\n'.join(values)


def compile_author(manuscript,version='0.1',reuse_figure=None):
    d=json.loads(manuscript.read_text());truth=validate(d);bp=load_ref(d['source_bindings']);b=next(x for x in json.loads(bp.read_text())['bindings']if x['id']==d['source_binding'])
    if reuse_figure:
        fp=load_ref(reuse_figure);fig=ref(fp)
    else:
        fp=manuscript.parent/(d['id']+'-figure-v'+version+'.svg');fig=figure(d,fp)
    visible=validate_figure_text(d,fp.read_bytes())
    tasks=[{k:q[k]for k in ['number','stem','options','answer']}|dict(rationale='；'.join(k+'：'+q['candidate_reasons'][k]for k in 'ABCD'))for q in d['questions']]
    alt='Four product cards in a two-by-two grid. '+'; '.join(visible.splitlines());body='!['+alt+']('+str(fp)+')';block=response_markdown(tasks)
    p=manuscript.parent/(d['id']+'-v'+version+'.md');ap=manuscript.parent/(d['id']+'-author-check-v'+version+'.json');assert not p.exists()and not ap.exists();p.write_text('# '+d['title']+'\n\n## 学生题面\n\n'+d['instruction']+'\n\n'+body+'\n\n<!-- responses:start -->\n\n'+block+'\n\n<!-- responses:end -->\n\n## 作者核对\n\n'+d['source_notice']+'\n')
    a=dict(version=version,id=d['id'],grade=7,questions=3,shop_grid_reading=True,candidate_sha256=ref(p)['sha256'],source_binding=b['id'],source_bindings=ref(bp),source_group_id=d['source_group_id'],manuscript=ref(manuscript),figure_asset=fig,review_response_tasks=tasks,canonical_response_block_sha256=hashlib.sha256(block.encode()).hexdigest(),student_passage=body,body_load_text=visible,choice_pair_audit=[dict(number=n,candidate=k,is_best=v,reason=d['questions'][n-1]['candidate_reasons'][k])for n,row in enumerate(truth,1)for k,v in row.items()],load_measure=dict(body_English_words=words(visible),figure_English_words_nonadditive=words(visible),image_alt_English_words=words(alt),stem_English_words=sum(words(q['stem'])for q in tasks),options_English_words_with_repeated_bank=sum(words(v)for q in tasks for k,v in q['options']),output_instruction_English_words=words(d['instruction']),output_response_positions=3),source_count_increment=0,authored_student_inputs_complete=True,independent_teacher_student_commercial_production_validated=False)
    ap.write_text(json.dumps(a,ensure_ascii=False,indent=2)+'\n');return dict(id=d['id'],grade=7,family=d['family'],family_label='阅读单选',title=d['title'],questions=3,candidate=ref(p),author_check=ref(ap),source_group_ids=[d['source_group_id']],instruction=d['instruction'],source_form_notice=d['source_notice'],format_summary='1完整四商品图表 / 2×2商品格 / 双店铺 / 降价、两件价、赠品 / 3题各4候选')


def check(g,a,b,s):
    d=json.loads(load_ref(a['manuscript']).read_text());truth=validate(d)
    sel=json.loads(load_ref(s['selected_native']).read_text());raw=load_ref(sel['source_native']).read_text()
    for span in sel['spans']:assert hashlib.sha256(raw[span['start']:span['end']].encode()).hexdigest()==span['sha256']
    assert s['features']==dict(materials=1,product_cards=4,rows=2,columns=2,responses=3,options_each=4,shops=2,offer_sequence=['day_discount','day_discount','two_for','free_gift'])
    assert s['full_question_text_and_necessary_chart_verified'] and not s['original_DOCX_acquired'] and not s['source_original_key_is_gold']
    assert not s['whole_reading_section_claimed_complete'] and s['source_question_numbers']==[46,47,48]
    assert sel['reference_keys']==list('DAA') and sel['actual_chart_and_published_text_internally_consistent_not_gold']
    assert len(g['requiredPassageImages'])==1 and g['requiredPassageImages'][0]['asset']==a['figure_asset']
    assert len(a['choice_pair_audit'])==12 and len(g['questions'])==b['responses']==3
    assert g['questions']==a['review_response_tasks'] and all(row[q['answer']]for row,q in zip(truth,g['questions']))
    visible=validate_figure_text(d,load_ref(a['figure_asset']).read_bytes());assert visible==a['body_load_text']
    assert 'Special prices apply' not in visible and visible.count(' on '+d['sale_day'])==2
    for item in d['items']:assert item['name'].capitalize()in visible and ' / '.join(item['colours'])in visible and item['store']in visible
    return True
