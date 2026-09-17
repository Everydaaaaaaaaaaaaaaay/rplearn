# -*- coding: utf-8 -*-
import importlib.util
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location('ledger', Path(__file__).parents[1] / 'verify-learning-program.py')
ledger = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ledger)


class LedgerChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        (self.root / 'evidence.md').write_text('Reviewable verification record')

    def task(self, name='A', status='complete', check_status='passed', deps=None):
        return {'id': name, 'status': status, 'depends_on': deps or [],
                'checks': [{'name': 'acceptance', 'status': check_status, 'evidence': ['evidence.md']}]}

    def run_check(self, tasks, version='WF-1.2'):
        return ledger.check({'workflow_version': version, 'tasks': tasks}, self.root, 'WF-1.2')

    def test_failed_verification_cannot_be_marked_complete(self):
        errors, _ = self.run_check([self.task(check_status='failed')])
        self.assertTrue(any('unresolved check' in e for e in errors))

    def test_unrelated_blocker_does_not_stop_actionable_work(self):
        blocked = self.task('A', 'blocked', 'blocked')
        blocked['blocker'] = 'Native app device access unavailable'
        errors, ready = self.run_check([blocked, self.task('B', 'ready', 'pending'), self.task('C', 'ready', 'pending', ['A'])])
        self.assertEqual(errors, [])
        self.assertEqual(ready, ['B'])

    def test_cycle_and_incomplete_dependency_are_rejected(self):
        errors, _ = self.run_check([self.task('A', deps=['B']), self.task('B', 'ready', 'pending', ['A'])])
        self.assertTrue(any('cycle' in e for e in errors))
        self.assertTrue(any('incomplete dependency' in e for e in errors))

    def test_missing_evidence_and_stale_version_are_rejected(self):
        (self.root / 'evidence.md').unlink()
        errors, _ = self.run_check([self.task()], 'WF-1.1')
        self.assertEqual(len(errors), 2)

    def test_verified_dependency_unlocks_next_task(self):
        errors, ready = self.run_check([self.task(), self.task('B', 'ready', 'pending', ['A'])])
        self.assertEqual(errors, [])
        self.assertEqual(ready, ['B'])


if __name__ == '__main__':
    unittest.main()
