# Opening-story dictionary translations — 2026-09-20

## Root cause and change

The interactive “出发前的小群聊” ChatStoryView supplied a translation closure that
always returned nil and disabled system fallback. No backend request occurred;
retry therefore failed immediately. Previous real-backend UI coverage exercised
normal chat, not this opening-story route.

OnboardingDependencies now requires DictExampleTranslationActions. Both first-run
onboarding and replay from settings receive the existing production resolver from
RootView. ChatStoryView forwards those actions and uses the standard fallback
policy: shared cache, bounded LLM retries, then Apple translation. This also wires
shared missing-example generation without a separate implementation.

Audited remaining onboarding call sites: the only fixed sample translation closure
is in WelcomeDictionaryScreen, a noninteractive marketing preview with hit testing
disabled, not a user dictionary entry point.

## Verification

Real production-backend UI regression advances the opening story to Ruby's flat
white message and opens flat, white and a. All eight displayed example translations
are asserted ready (4 + 2 + 2), with screenshots after scrolling the dictionary card.
No mock translation provider is used. Result: 1 passed, 0 failed, 0 skipped.

Command:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
TEST_RUNNER_RUN_LIVE_DICTIONARY_E2E=1 Scripts/test-ui.sh \
-only-testing:LingoTripUITests/DictionaryExampleFlowTests/testOpeningStoryExamplesUseLiveTranslations
```

Result bundle:
`build/DerivedData/VerificationResults/20260920T064752Z-79227.xcresult`.
Exported screenshots were visually inspected for the repaired translation rows.
App compiled in the Xcode UI test run; latest build installed and left running via
`Scripts/preview.sh preview home`. No backend change or deployment is needed.
Existing phone/TestFlight installations require the updated app build.
