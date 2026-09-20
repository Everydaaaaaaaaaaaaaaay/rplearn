# Dictionary popup dependency encapsulation — 2026-09-20

## Finding

Translation and retry algorithms were centralized, but every presenting Feature
still forwarded `DictExampleTranslationActions` through its own dependency bag,
overlay modifier and card initializer. Each entry could substitute a nil-returning
closure or disable Apple fallback. The opening-story failure was a real example of
this configuration gap, not a failed upstream model call.

## Ownership after this change

- RootView installs DictionaryPopupServices once around the entire root, including
  sheets, full-screen covers, authentication/onboarding and Xcode previews.
- AppEnvironment adapts the real backend resolver. Cache lookup, bounded LLM retries
  and missing-example generation continue using the existing production services.
- DictCardView reads the inherited service and owns the loading/display/retry flow.
  Its private content owns Apple fallback. Public card/overlay APIs and Feature
  dependency bags expose neither translation actions nor fallback-policy flags.
- Opening story, hands-on tutorial, chat, contact details, voice chat, encounters,
  activity pages, favorites, authored stories and grammar overlays all inherit the
  same configuration. A missing root configuration is an explicit diagnostic view
  and a Debug assertion, never an implicit nil translation provider.
- Static welcome content uses an explicitly noninteractive DictCardPreview. Its
  sample translations use a separate cache and cannot poison live lookup results.
- Context-specific callbacks for speech interruption and favorite attribution remain
  at the presentation boundary; they do not control example translation.

This preserves module boundaries: DictKit owns the popup behavior, BackendKit owns
network transport/retries, and App composes them. No Feature imports another Feature
or learns production endpoint/authentication details.

## Regression protection

`Scripts/check-architecture.sh --ios` now rejects Feature-level example translation
providers, service installation and fallback-policy forwarding. Public APIs no longer
accept those arguments, so old per-entry wiring also fails compilation.

Verification:

- 14 unit tests passed: DictExampleFallbackTests and
  BackendDictionaryExampleTranslationsTests. Result:
  `build/DerivedData/VerificationResults/20260920T072031Z-87904.xcresult`.
- 5 UI tests passed, zero skipped: all DictionaryExampleFlowTests plus
  OnboardingWelcomeTests/testWelcomeExplainsTheProductAndBeginsTheExistingOnboardingFlow.
  Real production dictionary services were enabled; opening-story flat/white/a,
  normal chat just/which, shared catalog reads and runtime example reuse all passed.
  Result: `build/DerivedData/VerificationResults/20260920T072130Z-88831.xcresult`.
- Opening-story screenshot inspected: all four flat examples show translations.
- iOS architecture and diff whitespace checks passed.
- Latest Debug build installed with `Scripts/preview.sh build home` and left running
  in the existing simulator.

No backend contract or deployment is required. Phones need the updated App build.
