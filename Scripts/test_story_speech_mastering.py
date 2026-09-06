"""Focused waveform invariants; synthetic signals, no model or download needed.
Run: python3 -m unittest discover -s Scripts -p test_story_speech_mastering.py
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import numpy as np

spec = importlib.util.spec_from_file_location('mastering', Path(__file__).with_name('master-story-speech.py'))
master = importlib.util.module_from_spec(spec)
spec.loader.exec_module(master)
R = master.RATE


def voice(seconds=.3):
    return (.05 * np.sin(2*np.pi*180*np.arange(round(seconds*R))/R)).astype(np.float32)


class MasteringTests(unittest.TestCase):
    def test_retains_quiet_expression_and_exact_voice_samples(self):
        breath = np.full(round(.3*R), .00009, dtype=np.float32)
        content = np.concatenate([breath, voice(), np.zeros(round(.4*R), dtype=np.float32)])
        trimmed, start, tail = master.trim_edges(content, preserve_expression=True)
        self.assertEqual(start, 0)
        np.testing.assert_array_equal(trimmed[300:len(breath)], breath[300:])
        np.testing.assert_array_equal(trimmed[len(breath):len(breath)+round(.3*R)], voice())
        self.assertGreater(tail, 0)

    def test_calibrates_total_gap_without_cutting_or_crossfading_speech(self):
        first = np.concatenate([voice(), np.zeros(round(.12*R), dtype=np.float32)])
        second = np.concatenate([np.zeros(round(.1*R), dtype=np.float32), voice()])
        combined, offsets, gaps = master.assemble([first, second], [.4, .2])
        self.assertAlmostEqual(gaps[0]['measured'], .4, places=4)
        np.testing.assert_array_equal(combined[:len(first)], first)
        start = round(offsets[1]*R)
        np.testing.assert_array_equal(combined[start:start+len(second)], second)
        self.assertEqual(len(combined) - start - len(second), round(.2*R))

    def test_never_cuts_retained_expression_to_force_short_gap(self):
        first = np.concatenate([voice(), np.zeros(round(.12*R), dtype=np.float32)])
        second = np.concatenate([np.zeros(round(.35*R), dtype=np.float32), voice()])
        combined, offsets, gaps = master.assemble([first, second], [.18, .1])
        self.assertEqual(gaps[0]['inserted'], 0)
        self.assertGreater(gaps[0]['measured'], .18)
        np.testing.assert_array_equal(combined[len(first):len(first)+len(second)], second)

    def test_silence_nonfinite_and_clipped_exports_are_rejected(self):
        with self.assertRaises(ValueError): master.trim_edges(np.zeros(R, dtype=np.float32))
        with tempfile.TemporaryDirectory() as root:
            for values in [np.array([0,np.nan]), np.array([0,1.01])]:
                with self.assertRaises(ValueError):master.write_audio(Path(root)/'bad.wav', values)

    def test_word_comparison_preserves_contractions_and_detects_missing_words(self):
        self.assertEqual(master.tokens("I'll ask. Nobody’s here."), ["i'll", 'ask', "nobody's", 'here'])
        self.assertEqual(master.edit_distance(master.tokens('A page, no questions.'),master.tokens('Page no questions.')),1)


if __name__=='__main__':unittest.main()
