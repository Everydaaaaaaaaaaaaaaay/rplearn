"""Expose subsequent source evidence without rewriting frozen authored payloads."""
import json
from datetime import date
from grade_mode_evidence import load_ref


def validate_update(update, review, groups):
    assert update['does_not_change_authored_input_or_answer'] is True and update['does_not_admit_source_audio_or_gold'] is True
    date.fromisoformat(update['checked_on'])
    assert isinstance(update['notice'], str) and update['notice'].strip()
    assert isinstance(update['label'], str) and update['label'].strip()
    assert review['scope'] == 'whole_independent_source_section_companion_followup'
    assert update['source_group_ids'] == [review['source_group_id']]
    targets = sorted(g['id'] for g in groups.values() if review['source_group_id'] in g['anchor_group_ids'])
    assert targets and sorted(update['author_group_ids']) == targets
    assert len(set(update['author_group_ids'])) == len(targets)
    assert review['source_written_input_layer_strengthened'] is True and review['whole_first_section_printed_inputs_verified'] is True
    assert all(review[k] is False for k in ['source_original_audio_acquired', 'whole_source_full_input_verified', 'source_key_independent_gold', 'original_school_release_authenticated', 'all_required_types_complete'])
    assert all(type(review[k]) is int and review[k] == 0 for k in ['new_authenticated_parent_papers', 'new_authored_groups', 'new_response_positions'])
    for ident in targets:
        audit = json.loads(load_ref(groups[ident]['author_check']).read_text())
        bindings = json.loads(load_ref(audit['source_bindings']).read_text())
        binding = next(b for b in bindings['bindings'] if b['id'] == audit['source_binding'])
        source = next(s for s in json.loads(load_ref(binding['source_index']).read_text())[binding['collection']] if s['id'] == binding['source_group_id'])
        assert source['id'] == review['source_group_id']
        assert source['features'] == review['configuration']
        assert len(groups[ident]['questions']) == review['configuration']['responses']
    return True


def load_updates(plan, groups):
    reference = plan.get('current_source_companion_updates')
    if not reference:
        return []
    index = json.loads(load_ref(reference).read_text())
    assert index['scope'] == 'source_companion_notes_separate_from_frozen_authored_groups'
    updates = index['updates']
    assert len({u['id'] for u in updates}) == len(updates)
    for update in updates:
        review = json.loads(load_ref(update['review']).read_text())
        validate_update(update, review, groups)
        for asset in review['evidence']:
            load_ref(asset)
    return updates
