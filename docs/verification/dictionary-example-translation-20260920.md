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

## Follow-up: instant tutorial translations and production cache failures

- Removed the tutorial's prepared translation table. Tutorial and normal cards now use the same production action factory.
- Marked Apple fallback results explicitly and excluded them from the reusable example cache; a later lookup retries the cloud path. Added a regression proving recovery to LLM and subsequent cache reuse.
- Live guest-authenticated generation reproduced a pending → missing result. PostgreSQL recorded `DICTIONARY_TRANSLATION_MODEL_MISMATCH`, while the underlying AI request was `succeeded`. The worker discarded successful output because it compared a provider model label with the configured alias.
- Worker now checks the configured route revision before and after generation, allowing provider canonical names while rejecting a configuration change during processing. Output validation remains required before cache writes.
- iOS suites: 11 passed (`20260920T035501Z-48896.xcresult`). First build encountered stale module metadata; rebuilding resolved it.
- The next live probe exposed a separate output rejection: the model emitted multiple glosses separated by semicolons. Prompt v3 now explicitly prohibits all list separators and requests only two fields, without a meaning index. Validation was not relaxed.
- Backend validation: 16 tests passed, TypeScript typecheck and focused ESLint passed.
- Deployment: initial artifact root permissions caused readiness failure and automatic rollback; corrected permissions and deployed `20260920-dictionary-llm-v3` successfully. Previous releases retained for rollback.
- Live authenticated guest probe succeeded on 2026-09-20 at 04:04:19 UTC: `Felix became a herpetologist instead` → `费利克斯转而成为了爬行动物学家。`, contextual gloss `转而`. State changed pending → ready, then another read returned the same generated timestamp and cache key. Configured model `deepseek-v4-flash@config-7`; actual provider alias observed `deepseek-flash`.
- Latest Debug build installed and launched successfully on the owner's iPhone; simulator preview also installed. No app data was cleared. The online generation/cache path was verified via API, not claimed as a completed phone UI walkthrough.
