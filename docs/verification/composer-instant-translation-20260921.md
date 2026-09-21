# Instant translation lifecycle and keyboard dismissal — 2026-09-21

The owner reported that Apple instant translation worked in the previous version but now remained pending, while AI translation completed quickly. These are separate providers: the instant path uses Apple's local TranslationSession; AI calls TranslationService.translateToEnglish via LLM. No language-pack failure has been established.

Changes:
- Move both local translation directions to independent sibling hosts at chat scope, outside the resizing safeAreaInset composer. Capture each session generation when constructing the host; stale callbacks cannot consume a later generation's queue.
- Move composer cancellation/recording cleanup from input-bar disappearance to chat-page disappearance. Layout-driven input-bar lifecycle changes must not own the translation session.
- Bound instant requests to 20 seconds (general fallback retains its 120-second default); stalled requests release continuations and can retry. Check cancellation again when registering a continuation.
- Blank chat taps and downward keyboard-dismiss gestures clear both English and Chinese focus. Preserve translator mode and drafts.

Verification:
- AppleTranslatorQueueTests + ComposerTranslationModelTests: 8 passed, 0 failed; `build/DerivedData/VerificationResults/20260921T123045Z-76455.xcresult`. Includes a never-started session timing out, subsequent retry, and stale-session completion isolation.
- ComposerTranslatorUITests: 1 passed, 0 failed; `build/DerivedData/VerificationResults/20260921T123220Z-77094.xcresult`. Includes blank-edge tap dismissing the Chinese keyboard without losing drafts, plus latest-message visibility and repeated panel toggles.
- Architecture and whitespace checks passed. Final build/preview includes moving cleanup to chat scope after the UI run.

Limit: the simulator does not provide Apple translation models. The handset is paired but not connected. The layout/session coupling is corrected, but actual restored Chinese-to-English output and the precise original runtime failure still require physical-device verification. Do not treat the queue tests as a successful on-device translation.
