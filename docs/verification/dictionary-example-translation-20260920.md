# Dictionary example translation reliability — 2026-09-20

Applies to the shared DictCardView used by tutorial, chat and encounters.

## Findings and changes

- Multiple example requests previously invalidated TranslationSession.Configuration before SwiftUI entered translationTask. Reserve the session synchronously when scheduling; requests arriving during execution wait for the next batch.
- Initial lookup rejected Apple's `supported` (not yet installed) language status while Retry permitted preparation. Initial lookup now permits the same system preparation/download flow; Apple may request user consent.
- Disappearance cancels continuations and timeouts. Generation checks reject availability results from an old lifecycle, inactive cards reject late upstream misses, and old batch completion cannot reset a reopened session.
- Initial fix used existing-translation-only lookup under the previous product policy. Superseded by the owner’s follow-up: cache → LLM (up to three attempts) → Apple. See the updated policy below.

## Verification

Xcode-hosted suites: DictExampleFallbackTests and BackendDictionaryExampleTranslationsTests. Cover concurrent first requests, requests arriving during translation, cancellation/reopening/late callbacks, supported language preparation, primary-hit bypass, fallback, and read-only backend hits/misses/pending results.

Apple's actual translation models are unavailable in Simulator. Queue tests inject availability and complete batches explicitly; they do not prove real-device model output. Device acceptance still needs: first open of `instead` with installed languages, first open without installed languages and consent, multiple examples, quick close/reopen, tutorial and regular chat. Genuine system/download errors remain retryable rather than being presented as successful translations.

Final result: 8 passed, 0 failed, 0 skipped.
Evidence: `build/DerivedData/VerificationResults/20260920T032335Z-41185.xcresult`.
Simulator preview installed from this tested build via `Scripts/preview.sh preview messages`.


## Updated owner policy: cache → LLM retries → Apple

- Example lookup first reads the shared PostgreSQL cache. On a miss it queues generation and polls the existing job. Failure permits up to two more generation attempts, with a delay. Success returns immediately and the existing worker persists the full-sentence translation and contextual meaning. Pending jobs are never duplicated; a bounded 91.5-second polling window per attempt permits Apple fallback if the worker remains stuck, and the worker can still cache its eventual result.
- Tutorial prepared examples remain reusable; other tutorial examples now use the same resolver as normal use, including guest authentication.
- Chat translations first check the message and an exact-sentence match in the current user's persisted messages. LLM errors and empty outputs retry up to three total attempts before Apple fallback. Successful translations are persisted to the message; subsequent opens and repeated sentences reuse them. No private chat text is placed in the globally shared dictionary cache.
- Retains the Apple session scheduling/lifecycle fixes from the previous commit.
- Existing uncommitted tutorial cloud-first translation changes and their tests are directly relevant to this policy and are included without reverting them.
- No backend source/schema changes or deployment required. Existing backend cache/worker tests: 14 passed.

Updated-policy iOS verification: 43 passed, 0 failed, 0 skipped.
Evidence: `build/DerivedData/VerificationResults/20260920T033241Z-43827.xcresult`.
Suites: TranslationServiceTests, BackendDictionaryExampleTranslationsTests, DictExampleFallbackTests, ChatWorkflowTests.
Backend command: `node node_modules/vitest/vitest.mjs run test/modules/dictionary-translation` (14 passed).
These are mocked-provider/queue tests, not live paid AI or real-device Apple model evaluations.
