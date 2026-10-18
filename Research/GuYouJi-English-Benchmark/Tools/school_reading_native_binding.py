"""Promote only the native grade10 section whose full author gate is implemented.

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
    expected=dict(original,source_native14_review=source['source_native14_review'],
                  native14_author_gate='grade10_care_notice14_v1',
                  authors_genre_model_ready=True,genre_substructure_further_review_before_authoring=False)
    assert source==expected
    assert source['level']==10 and source['configuration']['required_lists']==[]
    return True
