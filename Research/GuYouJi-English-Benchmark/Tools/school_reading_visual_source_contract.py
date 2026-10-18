"""Recover a known missing source input through explicit frozen visual evidence.

This path deliberately cannot use the unknown-to-text-readthrough exception.
The old observation and source bytes remain immutable; source answers stay untrusted.
"""
import json
import struct
from bs4 import BeautifulSoup
from grade_mode_evidence import load_ref


def validate(source):
    frozen=json.loads(load_ref(source['source_visual_recovery_review']).read_text())
    original=next(x for x in frozen['records'] if x['id']==source['id'])
    assert source['source_spans']==original['source_spans']
    assert source['source_observations']==original['source_observations']
    assert source['configuration']==original['configuration']
    overlay=source['necessary_input_overlay']
    assert overlay==original['necessary_input_overlay']
    assert source['visual_recovery_not_text_readthrough']
    assert 'source_member_input_confirmations' not in source
    assert source['configuration']['required_images']==['A.labelled_curve_graph']
    assert source['configuration']['necessary_images']
    assert overlay['previous_member_flag_false_preserved']
    assert overlay['raw_text_and_original_flags_not_overwritten']
    assert overlay['member_id']==source['source_observations'][0]['id']
    assert source['source_observations'][0]['necessary_input_complete'] is False
    assert all(o['necessary_input_complete'] is None for o in source['source_observations'][1:])
    for key in ['graph_answer_pointC_visible_at_catch_curve_peak',
                'low_high_fishing_pressure_axis_visible',
                'only_catch_curve_clearly_drawn_and_stock_label_floating_no_stock_line_inferred',
                'numeric_stock_percent_not_read_from_plot','B_phrase_visible_in_preview4']:
        assert overlay[key]
    assert overlay['B_unnamed_underlined_phrase']=='white-knuckling her way through'
    manifest=json.loads(load_ref(source['source_visual_fetch_manifest']).read_text())
    evidence=overlay['new_visual_input_evidence']
    assert len(evidence)==2 and overlay['graph_preview_page_position']==3
    for position,reference in zip([3,4],evidence):
        path=load_ref(reference);data=path.read_bytes()
        assert data[:8]==b'\x89PNG\r\n\x1a\n'
        width,height=struct.unpack('>II',data[16:24])
        assert (width,height)==(860,1216)
        row=next(r for r in manifest['records'] if r['path']==reference['path'])
        assert row['sha256']==reference['sha256'] and row['HTTP_status']==200
        assert row['preview_position1based']==position and row['paper_id']==source['paper_id']
        assert row['no_access_or_TLS_bypass']
        native=load_ref(dict(path=row['public_link_observed_in_cached_native'],sha256=row['native_sha256']))
        soup=BeautifulSoup(native.read_text(),'html.parser')
        assert soup.select('.asset-preview img')[position-1]['src']==row['url']
    assert overlay['graph_box_pixels']==[490,580,705,750]
    crop=load_ref(overlay['inspection_crop']).read_bytes()
    assert struct.unpack('>II',crop[16:24])==(860,680)
    confirmations=source['source_visual_input_confirmations']
    assert len(confirmations)==4
    for i,(sp,ob,confirmation) in enumerate(zip(source['source_spans'],source['source_observations'],confirmations)):
        assert confirmation==dict(member_id=ob['id'],source=sp['source'],whole_span_sha256=sp['sha256'],
            body_sha256=sp['body_sha256'],question_numbers=sp['question_numbers'],options_each=4,
            all_text_and_candidates_read=True,old_necessary_input_complete=ob['necessary_input_complete'],
            old_observation_retained=True,necessary_media=i==0,
            visual_evidence=evidence if i==0 else [evidence[1]] if i==1 else [],
            underlined_target=overlay['B_unnamed_underlined_phrase'] if i==1 else None,source_key_is_gold=False)
    return True
