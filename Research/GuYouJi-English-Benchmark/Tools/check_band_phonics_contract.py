"""Negative controls for preserving a whole band-only listening task."""
import copy
import json
from grade_mode_evidence import BASE, load_ref
from band_phonics_contract import validate_draft
from build_band_phonics_review import check


def run():
    index=json.loads((BASE/'CompleteCoverage20261017/BandPhonicsOriginals-v0.1.json').read_text())
    original=json.loads(load_ref(index['groups'][0]['manuscript']).read_text())
    validate_draft(original)
    changes=[lambda d:d.update(grade='primary2'),lambda d:d.update(mainland_grade_equivalence_established=True),
             lambda d:d.update(candidate_letters=['p','b','d']),lambda d:d['lists'][0]['items'][0].update(example=False),
             lambda d:d['clips'][0]['questions'].pop(),lambda d:d['lists'][1]['items'].pop(),
             lambda d:d['clips'][0]['questions'][0].update(owner='Anna'),
             lambda d:d['clips'][0]['questions'][0].update(acceptedAnswers=['p']),
             lambda d:d['clips'][0]['questions'][0].update(options=[['p','pear'],['b','bear']]),
             lambda d:d.update(render_repeat_count=2),lambda d:d['clips'][0].update(turns=[{'speaker':'M','text':'Nine isolated words.'}])]
    for alter in changes:
        d=copy.deepcopy(original);alter(d)
        try:validate_draft(d)
        except (AssertionError,KeyError,StopIteration):pass
        else:raise AssertionError('Malformed band draft admitted')
    return dict(negative_whole_task_controls=len(changes),positive_band_drafts=3,**check(BASE.parents[1]/'build/english-benchmark-quality-review/ks1-band-reference.html'))


if __name__=='__main__':print(json.dumps(run()))
