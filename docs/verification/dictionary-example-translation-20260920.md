# Dictionary example translation reliability — 2026-09-20

Applies to the shared DictCardView used by tutorial, chat and encounters.

## Findings and changes

- Multiple example requests previously invalidated TranslationSession.Configuration before SwiftUI entered translationTask. Reserve the session synchronously when scheduling; requests arriving during execution wait for the next batch.
- Initial lookup rejected Apple's `supported` (not yet installed) language status while Retry permitted preparation. Initial lookup now permits the same system preparation/download flow; Apple may request user consent.
- Disappearance cancels continuations and timeouts. Generation checks reject availability results from an old lifecycle, inactive cards reject late upstream misses, and old batch completion cannot reset a reopened session.
- The production client still used `generateOnMiss: true` and polling. Restore existing-translation-only lookup, with immediate Apple fallback for missing/pending results. No backend deployment is required for this client change.

## Verification

Xcode-hosted suites: DictExampleFallbackTests and BackendDictionaryExampleTranslationsTests. Cover concurrent first requests, requests arriving during translation, cancellation/reopening/late callbacks, supported language preparation, primary-hit bypass, fallback, and read-only backend hits/misses/pending results.

Apple's actual translation models are unavailable in Simulator. Queue tests inject availability and complete batches explicitly; they do not prove real-device model output. Device acceptance still needs: first open of `instead` with installed languages, first open without installed languages and consent, multiple examples, quick close/reopen, tutorial and regular chat. Genuine system/download errors remain retryable rather than being presented as successful translations.

Final result: 8 passed, 0 failed, 0 skipped.
Evidence: `build/DerivedData/VerificationResults/20260920T032335Z-41185.xcresult`.
Simulator preview installed from this tested build via `Scripts/preview.sh preview messages`.
