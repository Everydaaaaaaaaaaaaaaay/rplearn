# Top-5000 dictionary example completion

## Outcome

The frozen top-5000 frequency list previously contained 1,493 words with no valid
examples and 771 with one. Added 3,757 examples and their Chinese translations for
2,264 words, preserving existing relevant examples and original dictionary rows.
All 5,000 now display 2–4 examples: 4,014 / 427 / 559 words respectively, 11,545 total.
The prior 40-word / 80-example supplement remains intact.

Examples were generated and separately reviewed by DeepSeek Flash. Structural
validation rejected missing targets, duplicates, malformed POS and gloss lists.
Final assistant editorial corrections (including normal contraction spelling for
n't and common noun uses instead of rare verb uses) are recorded in the source.
This is not a claim of human lexicographic review or perfect future provider output.

## Online delivery

Production release `20260920-learner-catalog-v1` deployed successfully, including a
lemma catalog index. The existing operator-only import endpoint persisted all new
example/translation pairs. A public read-only endpoint returns latest reviewed
supplements; reads never trigger paid generation. Original historical records remain.
Rollback target is the preceding `20260920-dictionary-llm-v3`; this additive index and
seed can remain during rollback.

The client fetches when local display has fewer than two examples, with no permanent
negative cache. Translations delivered with catalog examples display immediately.
The bundled resource also contains the whole supplement for offline availability.
Existing installed clients need one update to acquire the catalog reader. Arbitrary
long-tail runtime English generation is outside this completion.

## Evidence

- Xcode-hosted tests: **40 passed, 0 failed/skipped**. Includes reading all 5,000
  entries from the actual bundled SQLite through DictDatabase and the actual Swift
  display policy, checking 2–4 examples, target relevance, uniqueness and new source
  cache identity. Also verifies unauthenticated catalog reads refresh after empty.
  `build/DerivedData/VerificationResults/20260920T052831Z-66875.xcresult`
- Real network UI tests: **2 passed, 0 failed/skipped**, covering just/which display
  and completed translations, plus the initially missing `the` examples fetched
  from production. No translation mocks. Final shared-catalog fixture removes only
  `the`'s new bundled senses to emulate the earlier dictionary version.
  `build/DerivedData/VerificationResults/20260920T053040Z-68102.xcresult`
- Before updating the bundle, the same catalog UI flow passed against the genuinely
  old bundled data, with screenshot inspected:
  `build/DerivedData/VerificationResults/20260920T052142Z-64535.xcresult`
- Real public API verification: **all 3,757 translation requests hit ready shared
  cache**, matching the imported sentence and contextual gloss after the server's
  documented NFKC normalization. Every request used generateOnMiss=false. Also
  checked 25 catalog samples across the frequency range, including n't.
- Backend: **17 tests passed**, TypeScript check, focused ESLint and architecture
  check passed (212 modules, 512 dependencies).
- SQLite integrity: ok. Applying both supplements twice to an in-memory database
  leaves the complete SQL dump unchanged. Offline seed self-test passed.

Reproduce data and online checks with `Tools/Dictionary/LearnerExamples/verify.py`;
see the adjacent source README for batch/import commands and provenance.

Latest simulator build installed and left running via `Scripts/preview.sh preview home`.
No App Store/TestFlight release was published as part of this work.
