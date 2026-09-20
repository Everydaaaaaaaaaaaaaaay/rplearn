# Dictionary example relevance and coverage — 2026-09-20

## Delivered scope

Filter displayed examples by complete headword/phrase or dictionary-attested word
forms, excluding synonym-only WordNet examples and substring collisions. Preserve
original dictionary records. Add 80 original English examples for 40 frequent
function words, including which, what, because and just. These examples are
assistant-authored and reviewed, not human-reviewed or copied from a corpus.
No runtime long-tail generation was added.

Supplemental examples have separate source identity and stable negative sense
ranks. The database build and offline translation export reproduce the same policy.
Translations retain the existing cache → LLM (up to three attempts) → Apple fallback
flow; there are no embedded Chinese translations for this batch.

## Verification

- Xcode-hosted DictDatabaseTests: 33 tests passed, including parameterized coverage
  of all 40 words, target matching and irregular inflections.
  Result: `build/DerivedData/VerificationResults/20260920T043049Z-55522.xcresult`.
- Live UI flow: contacts → Ruby → chat → Just dictionary → close → Which dictionary.
  Both supplemental rows for each word must contain completed Chinese translations;
  loading labels explicitly do not satisfy the assertion. Production resolver used,
  tutorial translation mock bypassed. One passed, zero failed/skipped.
  Result: `build/DerivedData/VerificationResults/20260920T043606Z-57172.xcresult`.
  Screenshot attachments: `just-target-examples`, `which-learner-examples`.
- Visually inspected exported screenshots. Both which translations completed;
  just shows the two target-word examples rather than merely/simply examples.
- Initial UI checks needed correction: tokenized text cannot be queried as one
  StaticText, and loading text shared the translated accessibility-label prefix.
  Final test uses individual example-row identities and excludes loading labels.
- Database integrity: `ok`. Applying the supplement twice to an in-memory copy
  leaves its complete SQL dump unchanged (idempotent).
- Offline seed pipeline self-test passed. Current display export: 7,788 jobs for
  3,507 words among the top 5,000; older larger counts included irrelevant examples.
- `Scripts/preview.sh preview home` installed and launched the latest simulator
  product. Physical iPhone was unavailable; this change has not been installed there.

## Limits

This is a bounded first supplement, not full-dictionary coverage. Live UI verification
covers just/which; all 40 words have database/display unit coverage. No new backend
code or deployment was needed. Live-provider outages cannot be ruled out by this run.
