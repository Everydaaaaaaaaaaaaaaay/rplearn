import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
import struct
import wave

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

    def test_review_date_uses_actual_review_day_and_rejects_invalid_dates(self):
        manifest = self.compile(review_change={'reviewedAt': '2026-10-29'})
        self.assertEqual(manifest['entries'][0]['unit']['authorship']['reviewedAt'], '2026-10-29')
        for date in ['2026-02-30', 'yesterday', '2026-10-29T00:00:00Z']:
            with self.assertRaisesRegex(ValueError, 'review date'):
                self.compile(review_change={'reviewedAt': date})

    def shared_source(self, family, level='undergraduate'):
        source = copy.deepcopy(self.source)
        original = next(u for u in self.originals.values() if u['level'] == level and u['originalGroup']['family'] == family)
        unit = source['units'][0]
        unit.update(sourceUnitId=original['id'], level=level, family=family)
        part = unit['materials'][0]
        part['text'] = '\n'.join(f'[{chr(65+i)}] Complete paragraph about detail {i}.' for i in range(11)) if family == 'paragraph_matching' else ' '.join(f'Context ____{i}____.' for i in range(1, 11))
        part['candidates'] = [chr(65+i) for i in range(11)] if family == 'paragraph_matching' else [f'word{i}' for i in range(15)]
        part['questions'] = [dict(prompt=f'Choose the answer for item {i+1}.', answer=i, explanation=(f'{chr(65+i)}段明确给出该信息，其他段讨论不同细节，不支持题干所述关系。' if family == 'paragraph_matching' else f'word{i}是上下文所定义的唯一动作，其他词的词性或语义与此处明确描述不符。')) for i in range(10)]
        return source

    def test_full_shared_bank_uses_lexical_rationales_and_once_only_keys(self):
        source = self.shared_source('shared_bank')
        self.assertEqual(len(self.compile(source)['entries'][0]['unit']['questions'][0]['options']), 15)
        source['units'][0]['materials'][0]['questions'][9]['answer'] = 0
        with self.assertRaisesRegex(ValueError, 'shared bank'):
            self.compile(source)

    def test_paragraph_matching_requires_complete_shared_paragraph_contract(self):
        source = self.shared_source('paragraph_matching')
        self.assertEqual(len(self.compile(source)['entries'][0]['unit']['questions']), 10)
        source['units'][0]['materials'][0]['candidates'] = source['units'][0]['materials'][0]['candidates'][:7]
        with self.assertRaisesRegex(ValueError, 'paragraph matching'):
            self.compile(source)

    def test_primary_shared_bank_keeps_its_own_short_contract(self):
        source = copy.deepcopy(self.source)
        original = next(u for u in self.originals.values() if u['level'] == 'primary5' and u['originalGroup']['family'] == 'shared_bank')
        source['units'][0].update(sourceUnitId=original['id'], level='primary5', family='shared_bank')
        self.assertEqual(len(self.compile(source)['entries'][0]['unit']['questions']), 3)

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

    def test_explicit_reviewed_picture_assets_are_copied_after_byte_checks(self):
        catalog = json.loads((ROOT / 'Backend/config/learning/originals/catalog.json').read_text())
        image = catalog['imageAssets'][0]
        source = copy.deepcopy(self.source)
        original = next(u for u in self.originals.values() if u['level'] == 'primary1' and u['originalGroup']['family'] == 'word_picture_matching')
        source['units'][0].update(sourceUnitId=original['id'], level='primary1', family='word_picture_matching')
        source['imageAssets'] = [image]
        for question in source['units'][0]['materials'][0]['questions']:
            question['materialImages'] = [{'assetId': image['id'], 'label': 'Reviewed whole picture sheet'}]
            question['optionImages'] = [image['id']] * len(question['options'])
        manifest = self.compile(source)
        self.assertEqual(manifest['imageAssets'], [image])
        question = manifest['entries'][0]['unit']['questions'][0]
        self.assertEqual(question['materialImages'][0]['assetId'], image['id'])
        self.assertEqual(question['options'][0]['imageAssetId'], image['id'])
        source['imageAssets'][0]['width'] += 1
        with self.assertRaisesRegex(ValueError, 'PNG|image'):
            self.compile(source)

    def test_owned_explicit_audio_is_bound_to_exact_transcript_voice_and_verified_bytes(self):
        catalog = json.loads((ROOT / 'Backend/config/learning/originals/catalog.json').read_text())
        audio = catalog['audioAssets'][0]
        source = copy.deepcopy(self.source)
        original = next(u for u in self.originals.values() if u['level'] == 'primary2' and u['originalGroup']['family'] == 'listening_word_phrase_choice')
        source['units'][0].update(sourceUnitId=original['id'], level=original['level'], family=original['originalGroup']['family'])
        source['audioAssets'] = [audio]
        for question in source['units'][0]['materials'][0]['questions']:
            question['audio'] = {'assetId': audio['id'], 'text': audio['transcript'], 'voice': audio['voice']}
        manifest = self.compile(source)
        self.assertEqual(manifest['audioAssets'], [audio])
        self.assertEqual(manifest['entries'][0]['unit']['questions'][0]['type'], 'listeningChoice')
        source['units'][0]['materials'][0]['questions'][0]['audio']['text'] = 'Invented different transcript'
        with self.assertRaisesRegex(ValueError, 'audio|transcript'):
            self.compile(source)

    def test_missing_declared_media_and_missing_audio_fail_closed(self):
        source = copy.deepcopy(self.source)
        source['units'][0]['materials'][0]['questions'][0]['materialImages'] = [{'assetId': 'image.' + '0' * 64, 'label': 'Missing image'}]
        with self.assertRaisesRegex(ValueError, 'image|media'):
            self.compile(source)
        source = copy.deepcopy(self.source)
        original = next(u for u in self.originals.values() if u['level'] == 'primary1' and u['originalGroup']['family'].startswith('listening'))
        source['units'][0].update(sourceUnitId=original['id'], level='primary1', family=original['originalGroup']['family'])
        with self.assertRaisesRegex(ValueError, 'audio|media'):
            self.compile(source)

    def test_long_reviewer_is_preserved_in_provenance_and_bounded_for_unit_display(self):
        reviewer = 'Same author review with a detailed declaration of limitations. ' * 3
        manifest = self.compile(review_change={'reviewer': reviewer})
        self.assertEqual(manifest['reviewer'], reviewer)
        self.assertLessEqual(len(manifest['entries'][0]['unit']['authorship']['reviewedBy']), 100)

    def test_native_schema_validation_happens_before_freezing_a_manifest(self):
        manifest = self.compile()
        self.compiler.validate_manifest(manifest)
        manifest['entries'][0]['unit']['authorship']['reviewedBy'] = 'x' * 101
        with self.assertRaisesRegex(ValueError, 'schema'):
            self.compiler.validate_manifest(manifest)

    def test_native_validation_decodes_large_chinese_text_without_chunk_corruption(self):
        manifest = self.compile()
        unit = manifest['entries'][0]['unit']
        for question in unit['questions']:
            question['material'] = '完整材料中的中文字符用于隔离编码验证。' * 700
        manifest['entries'][0]['contentHash'] = self.compiler.digest(unit)
        self.compiler.validate_manifest(manifest)

    def test_new_explicit_pcm_is_sha_bound_and_marked_for_selected_upload(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            media = root / 'Backend/config/learning/originals/media'
            media.mkdir(parents=True)
            (media.parent / 'catalog.json').write_text(json.dumps({'audioAssets': []}))
            draft = media / 'fixture.wav'
            with wave.open(str(draft), 'wb') as output:
                output.setnchannels(1)
                output.setsampwidth(2)
                output.setframerate(24000)
                output.writeframes(struct.pack('<h', 1000) * 24000)
            raw = draft.read_bytes()
            sha = hashlib.sha256(raw).hexdigest()
            audio = {'id': 'audio.' + sha, 'sha256': sha, 'byteSize': len(raw), 'durationMs': 1000, 'contentType': 'audio/wav', 'transcript': 'Engineering fixture clip only.', 'voice': 'research.local', 'reviewedAt': '2026-10-28', 'reviewNotes': 'Isolated PCM fixture, never production teaching content.'}
            draft.rename(media / (audio['id'] + '.wav'))
            self.compiler.ROOT = root
            source = copy.deepcopy(self.source)
            original = next(u for u in self.originals.values() if u['level'] == 'primary2' and u['originalGroup']['family'] == 'listening_word_phrase_choice')
            source['units'][0].update(sourceUnitId=original['id'], level=original['level'], family=original['originalGroup']['family'])
            source['audioAssets'] = [audio]
            for question in source['units'][0]['materials'][0]['questions']:
                question['audio'] = {'assetId': audio['id'], 'text': audio['transcript'], 'voice': audio['voice']}
            manifest = self.compile(source)
            self.assertEqual(manifest['newAudioAssetIds'], [audio['id']])
            self.assertEqual(manifest['audioAssets'], [audio])
            source['audioAssets'][0]['sha256'] = '0' * 64
            with self.assertRaisesRegex(ValueError, 'audio'):
                self.compile(source)


if __name__ == '__main__':
    unittest.main()
