# Encounter reading appearance — 2026-09-17

## Scope

Reported from the hands-on tutorial: the encounter character card and the top bar render dark, while the
story panel below stays light. The tutorial deliberately runs the production encounter screen
(`ActivitiesView` → `ActivityActionView`, see `95b538e`), so the same two surfaces appear in the tutorial
and in a production encounter.

## Root cause

The reading view draws the top bar and the identity card with `.regularMaterial`, while the page ink is the
fixed paper navy `Color.dsTravelNavy`. The frosted backdrop is the blurred scene photo, which stays bright in
both appearances, but materials follow the color scheme: in dark appearance they collapse to dark grey, so
navy text ends up on dark grey. The story panel was already a fixed `Color.white.opacity(0.90)` paper card,
which is why only the card and the top bar looked wrong.

Reproduced without touching a phone: launch the app with `UI_TEST_CAPTURE_APPEARANCE=dark` and the encounter
capture entry point (`UI_TEST_NATIVE_CAPTURE=encounter`, `UI_TEST_SOCIAL_FIXTURE=1`,
`UI_TEST_HOME_DESTINATION=activities`) on iPhone 17 Pro simulator `47DD7BF7-5378-47D7-ACC3-792EF8AAFF11`.

## Change

- The top bar, identity card and solitude card now render through `paperSurface(_:)`, which fills the shape
  with `.regularMaterial` pinned to the light appearance; paper ink stays navy. Light appearance is
  unchanged, dark appearance keeps the same frosted paper card instead of collapsing into grey.
- The tutorial was not forked. It runs the production encounter screen by design, so repairing the shared
  surface fixes the tutorial and production dark appearance together.

## Verification

- Forced-dark capture reviewed before and after: before, the card and top bar were dark grey under navy
  text; after, both are light frosted paper with the same look as the story panel. Light capture re-checked:
  identical to the pre-change light appearance.
- `Scripts/test-ui.sh -only-testing:LingoTripUITests/ActivitySceneTests -only-testing:LingoTripUITests/OnboardingWelcomeTests/testHandsOnTutorialUsesLocalTranslationDictionaryAndEncounter`:
  the tutorial walk, encounter appearance, translation/choice scrolling, word lookup, entrance-return and
  solitude tests passed.
- `testParkEncounterFriendshipAndJournal`, `testJourneyKeepsTabsAvailableAndCompletesOffscreen` and
  `testPondAndRainCafeContinueAcrossTwoRealLoopsAndLifecycleChanges` fail identically with this change
  stashed (verified by re-running on the unmodified tree), so they are pre-existing in this environment and
  unrelated to the appearance change.

## Open items

- Physical-phone dark-mode re-check of a production encounter is still owed.
- Scene media, provenance and the pending motion review are unchanged.
