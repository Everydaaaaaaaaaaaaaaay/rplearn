# Dictionary example source/render mismatch — 2026-09-20

## Reproduction and root cause

The bundled `laughing` entry has one example: `laughing children`. The live shared
catalog correctly supplies a distinct sentence:
`The laughing baby kicked her feet happily on the blanket.` Its Chinese translation
is `那个咯咯笑的宝宝在毯子上开心地踢着脚。`.

The card first renders the local example, then prepends the asynchronously fetched
shared example. Tappable text used a cache key based on word/POS/row index. TokenCache
accepted a cached value without checking its source text. The new first row therefore
rendered the old English tokens, while its model-derived annotation and translation
correctly described the baby sentence. Deduplication and database source sentences
were not at fault. Existing UI tests asserted model-derived row identifiers and
translations, which could not detect stale rendered token text.

## Repair

TokenCache now stores and compares the exact source string before returning cached
tokens. All call sites benefit, including updated messages, story text, favorites and
nested dictionary content. The dictionary also uses each example's stable identity
rather than its position as the tappable-text context.

Regression covers repeated same-key changes, returning to old text, streaming growth,
empty strings and multilingual text. The real-backend UI regression opens laughing
twice and checks actual rendered `baby` versus `children` word buttons inside their
respective rows, in addition to translations. No seed data or translation cache was
deleted, and no regeneration is needed.

## Verification

- `git diff --check` and `Scripts/check-architecture.sh --ios`: passed.
- Xcode-hosted `LingoTripTests/WordTokenizerTests`: 7 tests passed, zero failures
  or skips. Result: `build/DerivedData/VerificationResults/20260920T074024Z-93570.xcresult`.
- Live-backend `DictionaryExampleFlowTests/testInsertedExampleRendersItsOwnEnglishTokens`:
  passed, zero failures or skips. Result:
  `build/DerivedData/VerificationResults/20260920T074159Z-95172.xcresult`.
- Inspected the first-open screenshot: the full baby sentence and `laughing children`
  render separately, each with its matching Chinese translation. Reopening is covered
  by the same UI test.
- `Scripts/preview.sh preview home`: latest Debug app installed and launched on
  iPhone 17 Pro simulator `47DD7BF7-5378-47D7-ACC3-792EF8AAFF11`; left running.
- This is an iOS rendering fix. No backend deployment required; physical devices
  need an updated app build to receive it.
