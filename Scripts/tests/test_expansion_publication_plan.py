import importlib.util
from pathlib import Path
import unittest


class ExpansionPublicationPlanTests(unittest.TestCase):
    def setUp(self):
        path = Path(__file__).resolve().parents[2] / 'Backend/ops/native-server/publish-expansion-batches.py'
        self.assertTrue(path.exists())
        spec = importlib.util.spec_from_file_location('publication_plan', path)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.plan = {'run': '2026-10-28', 'batches': [{'batch': 'b000', 'hash': 'a' * 64}]}

    def test_commands_bind_run_hash_and_batch_without_shell_interpretation(self):
        command = self.module.commands(self.plan)[0]
        self.assertEqual(command[-5:], ['publish', 'b000', 'a' * 64, '--run', '2026-10-28'])
        self.assertIn('--max-old-space-size=128', command)

    def test_rejects_ambiguous_run_duplicate_or_unbounded_plan(self):
        invalid = [
            {**self.plan, 'run': '2026-10-29'},
            {**self.plan, 'batches': []},
            {**self.plan, 'batches': self.plan['batches'] * 2},
            {**self.plan, 'batches': [{'batch': f'b{i:03d}', 'hash': 'a' * 64} for i in range(4)]},
            {**self.plan, 'batches': [{'batch': 'b000;id', 'hash': 'a' * 64}]},
            {**self.plan, 'batches': [{'batch': 'b000', 'hash': 'not-reviewed'}]},
            {**self.plan, 'batches': [{'batch': 'b000', 'hash': 'a' * 64, 'extra': True}]},
        ]
        for value in invalid:
            with self.assertRaises(ValueError):
                self.module.commands(value)


if __name__ == '__main__':
    unittest.main()
