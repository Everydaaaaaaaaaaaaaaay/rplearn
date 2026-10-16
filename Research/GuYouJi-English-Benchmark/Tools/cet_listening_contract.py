"""Reject incomplete or visually leaked CET listening sections in the local page."""
import json
from urllib.parse import quote
from grade_mode_evidence import load_ref
from render_cet_listening import contract


def check(meta, group, audit, source):
    manuscript = json.loads(load_ref(audit['manuscript']).read_text())
    _, checked_source = contract(manuscript)
    assert checked_source == source
    generation = json.loads(load_ref(audit['audio_generation']).read_text())
    assert generation['manuscript'] == audit['manuscript']
    assert generation['whole_final_audio_decode_passed'] and generation['no_source_recording_reused']
    assert not generation['independent_listening_pronunciation_prosody_student_commercial_production_validated']
    assert audit['questions_per_extract'] == source['material']['responses_per_piece']
    assert audit['extracts'] == source['material']['pieces']
    assert audit['audio_transcript_in_teacher_only'] and audit['spoken_questions_in_teacher_only']
    assert len(audit['audio_assets']) == len(generation['tracks']) == len(group['requiredAudioAssets']) == 1
    asset, track, display = audit['audio_assets'][0], generation['tracks'][0], group['requiredAudioAssets'][0]
    load_ref(asset)
    assert asset['sha256'] == track['sha256'] and asset['repeat_count'] == track['repeat_count'] == display['repeat_count'] == 1
    assert asset['sha256'] not in {a['sha256'] for a in source['original_audio_assets']}
    assert asset['response_numbers'] == display['response_numbers'] == list(range(1, source['responses']+1))
    assert display['asset'] == {k: asset[k] for k in ['path', 'sha256']}
    assert display['src'] == '../../'+quote(asset['path'])
    assert abs(asset['seconds']-track['seconds']) < .01
    assert track['decoded_frames'] > 0 and track['peak_abs_sample'] > 0
    segments = track['segments']
    assert all(s['repeat'] == 1 for s in segments)
    assert not any(s['role'] == 'repeat_instruction' for s in segments)
    expected_order = []
    next_number = 0
    for p, clip in enumerate(manuscript['clips'], 1):
        expected_order += [('material', p, None)]*len(clip['turns'])
        for _ in clip['questions']:
            next_number += 1
            expected_order += [('spoken_question', p, next_number)]
    assert [(s['role'], s['piece'], s['question']) for s in segments
            if s['role'] in {'material', 'spoken_question'}] == expected_order
    number = 0
    for p, clip in enumerate(manuscript['clips'], 1):
        recorded = [s for s in segments if s['role'] == 'material' and s['piece'] == p]
        assert [(s['speaker'], s['text']) for s in recorded] == [(t['speaker'], t['text']) for t in clip['turns']]
        for t in clip['turns']:
            assert t['text'] in group['reviewText'] and t['text'] not in group['passageHtml']
        for q in clip['questions']:
            number += 1
            spoken = [s for s in segments if s['role'] == 'spoken_question' and s['question'] == number]
            assert len(spoken) == 1 and spoken[0]['piece'] == p
            assert spoken[0]['text'] == str(number)+'. '+q['spoken_question']
            pauses = [s for s in segments if s['role'] == 'answer_pause' and s['question'] == number]
            assert len(pauses) == 1 and pauses[0]['end_frame']-pauses[0]['start_frame'] == 15*track['sample_rate']
            task = group['questions'][number-1]
            assert task['stem'] == f'第{number}题（问题在录音中）'
            assert task['answer'] == q['answer'] and task['options'] == q['options']
            assert q['spoken_question'] in group['reviewText']
            assert q['spoken_question'] not in group['passageHtml']
            if group['studentBeforeHtml']:
                assert q['spoken_question'] not in group['studentBeforeHtml']
    assert number == source['responses']
    assert len([s for s in segments if s['role'] == 'spoken_question']) == number
    assert len([s for s in segments if s['role'] == 'answer_pause']) == number
    assert audit['load_measure']['audio_dialogue_English_words_once'] == track['dialogue_words_once']
    assert audit['load_measure']['audio_question_English_words_once'] == track['spoken_question_words']
    assert audit['load_measure']['audio_spoken_words_including_repetition_and_introductions'] == track['spoken_words_with_instructions']
