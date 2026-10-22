import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / 'Research/GuYouJi-English-Benchmark/Tools'
spec = importlib.util.spec_from_file_location(
    'presentation', TOOLS / 'learning_original_presentation.py')
presentation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(presentation)


class OriginalOptionLabelsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.revisions = json.loads((TOOLS.parent /
            'FirstRelease/tool-option-label-revisions-v0.1.json').read_text())
        # Immutable v1 evidence, independent of the revised publication catalog.
        cls.base = json.loads(subprocess.check_output([
            'git', 'show', 'f0faf35b:Backend/config/learning/originals/catalog.json'],
            cwd=ROOT))

    def test_names_replace_descriptions_without_losing_reading_or_grading(self):
        revised = presentation.apply_option_labels(self.base, self.revisions)
        ids = {r['unitId'] for r in self.revisions['units']}
        changed = 0
        for old, new in zip(self.base['units'], revised['units']):
            if old['unit']['id'] not in ids:
                self.assertEqual(old, new)
                continue
            changed += 1
            self.assertEqual(new['unit']['version'], 2)
            self.assertEqual(old['unit']['originalGroup'], new['unit']['originalGroup'])
            self.assertEqual(old['probes'], new['probes'])
            for before, after in zip(old['unit']['questions'], new['unit']['questions']):
                self.assertEqual(before['answer'], after['answer'])
                self.assertEqual(before['prompt'], after['prompt'])
                self.assertEqual(before['explanation'], after['explanation'])
                self.assertEqual([o['id'] for o in before['options']],
                                 [o['id'] for o in after['options']])
                self.assertTrue(all(len(o['text']) < 25 for o in after['options']))
        self.assertEqual(changed, 3)
        first = next(e['unit'] for e in revised['units']
                     if e['unit']['id'] == 'original.grade8-learner-tools-profile-matching')
        self.assertEqual([o['text'] for o in first['questions'][0]['options']],
                         ['A. StoryTrack', 'B. SpeakPair', 'C. ListenReplay', 'D. WriteFix'])
        self.assertEqual([q['answer'] for q in first['questions']], ['o2', 'o0', 'o3'])
        self.assertEqual(revised['batches'][-1]['unitIds'],
                         [r['unitId'] for r in self.revisions['units']])

    def test_rejects_unreviewed_input_and_misidentified_tool(self):
        changed = copy.deepcopy(self.base)
        entry = next(e for e in changed['units'] if e['unit']['id'] ==
                     self.revisions['units'][0]['unitId'])
        entry['unit']['questions'][0]['answer'] = 'o0'
        with self.assertRaisesRegex(ValueError, 'Reviewed base changed'):
            presentation.apply_option_labels(changed, self.revisions)
        wrong = copy.deepcopy(self.revisions)
        wrong['units'][0]['optionLabels']['o0'] = 'A. InventedTool'
        with self.assertRaisesRegex(ValueError, 'description/name binding changed'):
            presentation.apply_option_labels(self.base, wrong)


if __name__ == '__main__':
    unittest.main()
