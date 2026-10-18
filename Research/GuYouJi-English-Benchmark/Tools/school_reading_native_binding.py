"""Bind native fourteen-response sections to their implemented author gates.

Frozen source observations and the printed key remain unchanged. Readiness is
an explicit successor overlay; it is not a source/key/rights admission.
"""
import json
from pathlib import Path
from grade_mode_evidence import load_ref
from check_school_native_reading import validate as validate_native


def validate(source):
    document=json.loads(load_ref(source['source_native14_review']).read_text())
    original=next(r for r in document['records']if r['id']==source['id'])
    prior=json.loads(load_ref(document['previous_reconciliation']).read_text())
    acquisitions={r['id']:r for r in json.loads((Path(__file__).resolve().parents[1]/'Registry/acquisitions.json').read_text())['acquisitions']}
    validate_native(original,prior,acquisitions)
    gates={10:'grade10_care_notice14_v1',11:'grade11_profile_research14_v1'}
    expected=dict(original,source_native14_review=source['source_native14_review'],
                  native14_author_gate=gates[original['level']],
                  authors_genre_model_ready=True,genre_substructure_further_review_before_authoring=False)
    assert source==expected
    if source['level']==10:
        assert source['configuration']['required_lists']==[]
    else:
        assert source['configuration']['required_lists']==['A.benefits_requirements_and_service_bullet_lists']
        assert len(source['illustrative_source_media'])==2
    return True
