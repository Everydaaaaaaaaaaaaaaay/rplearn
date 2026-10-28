import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
COMPILER = ROOT / 'Scripts/compile-learning-expansion-20261028.py'


class ExpansionCompilerTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(COMPILER.exists(), 'Dedicated reviewed compiler is missing')
        spec = importlib.util.spec_from_file_location('expansion28', COMPILER)
        self.compiler = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.compiler)
        entries = json.loads((ROOT / 'Backend/config/learning/originals/catalog.json').read_text())['units']
        self.originals = {entry['unit']['id']: entry['unit'] for entry in entries}
        original = next(u for u in self.originals.values() if u['level'] == 'primary4' and u['originalGroup']['family'] == 'reading_choice')
        self.source = {'createdAt': '2026-10-28T00:00:00Z', 'reviewBoundary': 'Same-author review only; no independent teacher review or learner calibration claimed.', 'units': [
            {'id': 'primary4.fixture-reading', 'sourceUnitId': original['id'], 'level': 'primary4', 'family': 'reading_choice', 'title': '四年级阅读：图书馆的开放时间', 'minutes': 8,
             'materials': [{'id': 'reading', 'title': 'A Library Notice', 'text': 'The library opens at nine. It closes at five. Please bring your card.', 'questions': [
                 {'prompt': prompt, 'options': ['Nine.', 'Five.', 'Seven.'], 'answer': 0, 'explanation': 'A正确：原文明说九点。B是关闭时间；C原文没有七点。'}
                 for prompt in ['When does the library open?', 'Which opening time is in the notice?', 'What time can you first enter?']]}]}]}

    def compile(self, source=None, review_change=None):
        source = source or self.source
        raw = json.dumps(source, ensure_ascii=False).encode()
        review = {'sourceSHA256': hashlib.sha256(raw).hexdigest(), 'reviewKind': 'author-self-review', 'reviewer': 'Same author', 'units': [{'id': u['id'], 'status': 'approved', 'findings': []} for u in source['units']]}
        if review_change:
            review.update(review_change)
        return self.compiler.compile_manifest(raw, json.dumps(review).encode(), self.originals, 'b000')

    def test_deterministic_serialization_preserves_explicit_text_and_keys(self):
        a = self.compile()
        self.assertEqual(a, self.compile())
        self.assertEqual(a['run'], '2026-10-28')
        question = a['entries'][0]['unit']['questions'][0]
        self.assertEqual(question['answer'], 'o0')
        self.assertEqual(question['explanation'], self.source['units'][0]['materials'][0]['questions'][0]['explanation'])
        self.assertEqual(a['entries'][0]['unit']['originalGroup']['family'], 'reading_choice')
        self.assertTrue(question['instruction'].isascii())

    def test_rejects_unbound_review_wrong_level_wrong_family_and_unexplained_distractor(self):
        with self.assertRaisesRegex(ValueError, 'SHA'):
            self.compile(review_change={'sourceSHA256': '0' * 64})
        for key, value in [('level', 'primary5'), ('family', 'choice_cloze')]:
            changed = copy.deepcopy(self.source)
            changed['units'][0][key] = value
            with self.assertRaisesRegex(ValueError, 'source.*(level|family)|source binding'):
                self.compile(changed)
        changed = copy.deepcopy(self.source)
        changed['units'][0]['materials'][0]['questions'][0]['explanation'] = 'A正确。B错误。'
        with self.assertRaisesRegex(ValueError, 'distractor'):
            self.compile(changed)

    def test_rejects_bad_keys_chinese_instructions_and_unapproved_review(self):
        changed = copy.deepcopy(self.source)
        changed['units'][0]['materials'][0]['questions'][0]['answer'] = 3
        with self.assertRaisesRegex(ValueError, 'key'):
            self.compile(changed)
        changed = copy.deepcopy(self.source)
        changed['units'][0]['instruction'] = '请选择正确答案。'
        with self.assertRaisesRegex(ValueError, 'English'):
            self.compile(changed)
        with self.assertRaisesRegex(ValueError, 'review'):
            self.compile(review_change={'units': []})

    def test_output_is_immutable_and_index_update_is_repeatable(self):
        manifest = self.compile()
        with tempfile.TemporaryDirectory() as temporary:
            directory = Path(temporary)
            self.compiler.write_manifest(manifest, directory)
            self.compiler.write_manifest(manifest, directory)
            self.assertEqual(json.loads((directory / 'index.json').read_text())['batches'], ['b000'])
            changed = copy.deepcopy(manifest)
            changed['entries'][0]['unit']['title'] = '不能改写已冻结题组'
            with self.assertRaisesRegex(ValueError, 'Frozen'):
                self.compiler.write_manifest(changed, directory)


if __name__ == '__main__':
    unittest.main()
