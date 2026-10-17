"""Reject substring/empty keys using current whole manuscripts, without rewriting them."""
import copy
import json
from types import SimpleNamespace
from unittest.mock import patch

from check_all_levels_review import extract
from grade_mode_evidence import REPO, load_ref
import junior_listening_contract
import senior_short_listening_contract
import shared_picture_listening_contract
import compile_inherited_cloze
import compile_inherited_reading
import compile_academic_features
import compile_academic_visual
import compile_multi_question_listening


INVALID = ['', 'AB', 'BC', 'ABC', 'A ', 'a', 'Z', None, 0, ['A']]


def source_for(audit):
    bindings = json.loads(load_ref(audit['source_bindings']).read_text())
    binding = next(b for b in bindings['bindings'] if b['id'] == audit['source_binding'])
    index = json.loads(load_ref(binding['source_index']).read_text())
    source = next(s for s in index[binding.get('collection', 'groups')]
                  if s['id'] == binding['source_group_id'])
    return binding, source


def run():
    page = extract(REPO/'build/english-benchmark-quality-review/index.html')
    records = []
    for group in page['groups'].values():
        audit = json.loads(load_ref(group['author_check']).read_text())
        if not audit.get('manuscript'):
            continue
        draft = json.loads(load_ref(audit['manuscript']).read_text())
        checks = []
        # Each mutation replaces one exact single-choice key, retaining the whole input.
        for flag, module in [('junior_source_bound', junior_listening_contract),
                             ('senior_short_source_bound', senior_short_listening_contract),
                             ('shared_picture_listening', shared_picture_listening_contract)]:
            if audit.get(flag) and draft['clips'][0]['questions'][0].get('options'):
                checks.append((flag, module.validate_draft,
                               lambda d: d['clips'][0]['questions'][0]))
                if draft.get('worked_example'):
                    checks.append((flag + ':worked_example', module.validate_draft,
                                   lambda d: d['worked_example']['question']))
        for flag, module, question in [
            ('inherited_complete_cloze', compile_inherited_cloze, lambda d: d['questions'][0]),
            ('inherited_cet_reading', compile_inherited_reading, lambda d: d['passages'][0]['questions'][0]),
            ('academic_matching_features', compile_academic_features, lambda d: d['items'][0]),
            ('academic_summary_or_diagram', compile_academic_visual, lambda d: d['items'][0]),
        ]:
            if not audit.get(flag) or not question(draft).get('answer'):
                continue
            binding, source = source_for(audit)
            if flag in ['inherited_complete_cloze', 'inherited_cet_reading']:
                validate = lambda d, m=module, b=binding, s=source: m.validate(d, b, s)
            else:
                validate = lambda d, m=module, s=source: m.validate(d, s)
            checks.append((flag, validate, question))
        if audit.get('multi_question_listening'):
            binding, source = source_for(audit)

            def validate_multi(d, g=group, a=audit, b=binding, s=source):
                # Alter both printed output and manuscript so output equality does not
                # hide the label-membership check. All source/audio refs remain pinned.
                shown = copy.deepcopy(g)
                shown['questions'][0]['answer'] = d['clips'][0]['questions'][0]['answer']
                real_loader = compile_multi_question_listening.load_ref

                def loader(ref):
                    if ref == a['manuscript']:
                        return SimpleNamespace(read_text=lambda: json.dumps(d))
                    return real_loader(ref)

                with patch.object(compile_multi_question_listening, 'load_ref', loader):
                    return compile_multi_question_listening.check(shown, a, b, s)

            checks.append(('multi_question_listening', validate_multi,
                           lambda d: d['clips'][0]['questions'][0]))
        for flag, validate, question in checks:
            validate(draft)
            for value in INVALID:
                malformed = copy.deepcopy(draft)
                question(malformed)['answer'] = value
                try:
                    validate(malformed)
                except AssertionError:
                    pass
                else:
                    raise AssertionError((group['id'], flag, 'invalid key admitted', value))
            records.append(dict(id=group['id'], contract=flag,
                                malformed_keys_rejected=len(INVALID)))
    assert records, 'No current manuscripts exercised'
    return dict(positive_whole_drafts=len({r['id'] for r in records}),
                positive_contract_paths=len(records),
                negative_controls=sum(r['malformed_keys_rejected'] for r in records),
                original_manuscripts_modified=False, records=records)


if __name__ == '__main__':
    print(json.dumps(run(), ensure_ascii=False, indent=2))
