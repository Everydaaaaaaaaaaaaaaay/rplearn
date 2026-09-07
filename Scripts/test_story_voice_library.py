#!/usr/bin/env python3
"""Cheap, deterministic checks for production planning. No model calls."""
import importlib.util, json, unittest, unicodedata
from pathlib import Path

HERE=Path(__file__).resolve().parent

def load(name,file):
    spec=importlib.util.spec_from_file_location(name,HERE/file); module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
plan=load('plan','plan-story-voices.py')
production=load('production','produce-story-voices.py')

class StoryVoicePlanningTests(unittest.TestCase):
    def test_all_supported_pages_and_only_supported_pages_are_covered(self):
        result=plan.build(); spoken={(c['story'],c['node']) for c in result['clips']}; silent={(c['story'],c['node']) for c in result['silent']}
        self.assertFalse(spoken&silent)
        self.assertEqual(len(spoken),len(result['clips']))
        for path in (plan.ROOT/'App/Resources/Stories').glob('*.json'):
            if not path.stem.startswith('departures_'):continue
            story=json.loads(path.read_text())
            if 'nodes' not in story:continue
            for n in story['nodes']:
                if 'text' not in n:continue
                key=(story['id'],n['id']);self.assertIn(key,spoken|silent)
                if n.get('choices') or n['speaker'] in ['你','你的选择'] or any('\u3400'<=c<='\u9fff' for c in n['text']):self.assertIn(key,silent)
                else:self.assertIn(key,spoken)

    def test_segments_preserve_all_words_numbers_and_fit_real_renderer(self):
        for clip in plan.build()['clips']:
            with self.subTest(story=clip['story'],node=clip['node']):
                self.assertEqual(plan.words(clip['sourceText']),plan.words(' '.join(s['text'] for s in clip['segments'])))
                for s in clip['segments']:
                    text=('<breath> ' if s['breath'] else '')+s['text']
                    self.assertLessEqual(len(unicodedata.normalize('NFKD',text)),70)
                    self.assertTrue(.88<=s['rate']<=1.1)
                    self.assertTrue(0<=s['gapAfter']<=1.2)
                    if clip['speaker'] in ['旁白','出发之后']:self.assertFalse(s['breath'])

    def test_number_and_spelling_normalization_does_not_hide_missing_words(self):
        self.assertEqual(production.canonical('Wharf 3.'),production.canonical('Wharf three.'))
        self.assertNotEqual(production.canonical('Wharf 3.'),production.canonical('Wharf four.'))
        self.assertNotEqual(production.canonical('On a boat.'),production.canonical('A boat.'))
        self.assertNotEqual(production.canonical("It isn't an emergency."),production.canonical('It is an emergency.'))
        self.assertNotEqual(production.canonical('I promised.'),production.canonical('I promise.'))
        self.assertEqual(production.canonical('the colours'),production.canonical('the colors'))

    def test_cast_stays_fixed_across_cities_and_branches(self):
        voices={}
        for clip in plan.build()['clips']:
            for segment in clip['segments']:voices.setdefault(clip['cast'],set()).add(segment['voice'])
        self.assertTrue(all(len(v)==1 for v in voices.values()))
        self.assertEqual(voices['Oliver'],{'M5'})
        self.assertEqual(voices['Nora'],{'F5'})
        self.assertEqual(voices['Ruby'],{'F3'})
        self.assertEqual(voices['Marcus'],{'M3'})

if __name__=='__main__':unittest.main()
