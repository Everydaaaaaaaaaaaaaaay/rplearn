"""Complete graph-reading section input and authored consistency checks.

The fictional single-curve model improves the original ambiguous dual-metric
axis; it is an authored design choice, not a reconstruction of source data.
"""
import base64
import hashlib
import html
import re
from grade_mode_evidence import load_ref

OPERATIONS=['competing_policy_goals','graph_unique_peak','model_population_explanation',
 'memoir_personal_scope','context_phrase_meaning','review_structure','whole_review_title',
 'specific_mechanism_detail','surface_water_movement','blockage_prevention','secondary_application',
 'research_scope_reason','context_routine_comparison','access_vs_interaction','bounded_support_implication']


def graph_alt(m):
    labels=m['point_labels']
    return (m['title']+'. Horizontal axis: '+m['x_axis']+', low to high. Vertical axis: '+m['y_axis']+
        '. A single smooth curve starts at zero at '+labels[0]+', rises through '+labels[1]+
        ', reaches its only peak at '+labels[2]+', and falls to zero at '+labels[3]+'. No stock curve or numerical measurements are shown.')


def graph_svg(m):
    labels=m['point_labels'];coords=[(90,320),(217.5,147.5),(345,90),(600,320)]
    points=''.join('<circle cx="'+str(x)+'" cy="'+str(y)+'" r="5" fill="#152c37"/><text x="'+str(x-15)+'" y="'+str(y-14)+'">'+label+'</text>' for label,(x,y)in zip(labels,coords))
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="700" height="420" viewBox="0 0 700 420" role="img" aria-labelledby="title desc">'
        '<title id="title">'+html.escape(m['title'])+'</title><desc id="desc">'+html.escape(graph_alt(m))+'</desc>'
        '<rect width="700" height="420" fill="white"/><g font-family="Arial,sans-serif" font-size="18" fill="#152c37">'
        '<text x="350" y="30" text-anchor="middle">'+html.escape(m['title'])+'</text>'
        '<path d="M90 50V320H630" fill="none" stroke="#152c37" stroke-width="2"/>'
        '<path d="M90 320Q345 -140 600 320" fill="none" stroke="#166e78" stroke-width="4"/>'+points+
        '<text x="90" y="350" text-anchor="middle">Low</text><text x="600" y="350" text-anchor="middle">High</text>'
        '<text x="350" y="390" text-anchor="middle">'+html.escape(m['x_axis'])+'</text>'
        '<text transform="translate(30 200) rotate(-90)" text-anchor="middle">'+html.escape(m['y_axis'])+'</text></g></svg>\n')


def validate(d,s):
    c=s['configuration']
    assert c['response_distribution']==[3,4,4,4] and c['points_each']==2.5
    assert c['required_images']==['A.labelled_curve_graph'] and s['source_visual_input_confirmations']
    assert d['source_bound_graph_reading_section']
    assert [q['operation']for q in d['questions']]==OPERATIONS
    m=d['graph_model'];assert sorted(m['point_labels'])==list('ABCD')
    assert m['title'] and m['x_axis'] and m['y_axis']
    assert m['fictional_single_curve_not_source_reconstruction']
    assert m['plot_equation']=='4*x*(1-x), 0<=x<=1'
    assert m['point_x']==[0,0.25,0.5,1] and m['point_y']==[0,0.75,1,0]
    assert m['graph_alt']==graph_alt(m)
    raw=load_ref(d['graph_asset']).read_text()
    assert raw==graph_svg(m)
    embed='!['+graph_alt(m)+']('+d['graph_asset']['path']+')'
    assert d['sections'][0]['units'][0].count(embed)==1
    assert sum(u.count('![')for sec in d['sections']for u in sec['units'])==1
    qs=d['questions'];assert dict(qs[1]['options'])=={k:k for k in 'ABCD'}
    assert qs[1]['answer']==m['point_labels'][2]
    target=d['lexical_target'];pnum=d['lexical_paragraph']
    b=d['sections'][1]['units'][0].split('\n\n')
    assert '**'+target+'**' in b[pnum-1] and target in qs[4]['stem']
    assert 'paragraph '+str(pnum) in qs[4]['stem']
    assert d['book_review_not_memoir_excerpt'] and d['hearing_not_ethnic_generalisation_or_clinical_trial']
    for field in ['treatment','water_transport','untreated_area','drainage','secondary_use']:
        assert d['mechanism_evidence'][field] in d['sections'][2]['units'][0]
    assert d['model_evidence'] in d['sections'][0]['units'][0]
    for field in ['selection_limit','access','interaction','contextual_support']:
        assert d['hearing_evidence'][field] in d['sections'][3]['units'][0]
    assert len(d['answer_evidence'])==15
    for q,ev in zip(qs,d['answer_evidence']):
        assert ev['number']==q['number'] and ev['best_text']==dict(q['options'])[q['answer']]
        if q['number']==2:
            assert ev['graph_SHA']==d['graph_asset']['sha256'] and ev['peak_point']==m['point_labels'][2]
        else:
            body=d['sections']['ABCD'.index(q['materialLabel'])]['units'][0]
            assert ev['evidence'] in body and len(ev['evidence'])>20
    return True


def check_rendered(g,a,d):
    assert a['source_bound_graph_reading_section']
    for field in ['graph_asset','graph_model','mechanism_evidence','hearing_evidence','answer_evidence']:
        assert a[field]==d[field]
    images=g['requiredPassageImages'];assert len(images)==1
    im=images[0];assert im['asset']==d['graph_asset'] and (im['width'],im['height'])==(700,420)
    assert im['alt']==graph_alt(d['graph_model'])
    raw=base64.b64decode(im['src'].split(',',1)[1])
    assert hashlib.sha256(raw).hexdigest()==d['graph_asset']['sha256']
    assert g['passageHtml'].count('class="passage-image"')==1
    assert a['load_measure']['graph_label_English_words']>0
    assert a['load_measure']['graph_alt_English_words']>a['load_measure']['graph_label_English_words']
    return True
