# Chat and dictionary translation routes — 2026-09-17

## Scope

Two translation entry points must stay independently controllable from the AI console, and both must
prefer cloud model output over on-device machine translation:

- chat sentence translation, long-press → 翻译 (`translation`)
- dictionary example translation in the word popup (`dictionary_example_translation`)

## Change

- AI console route management: `translation` is listed again (it had been hidden together with the retired
  `speech_feedback`). `dictionary_example_translation` keeps its own row, so the two translation tasks can
  be switched to different providers/models, temperatures and limits. Bulk switch and version history cover
  both. The console already maps both task names to Chinese labels.
- The dictionary example route stays the generation path: the worker calls the AI gateway with
  `task: "dictionary_example_translation"`, and the cache identity embeds `model@config-<version>` from
  `routeIdentity`, so switching the model in the console invalidates existing example translations and
  regenerates them with the new model instead of serving stale output.
- iOS `BackendDictionaryExampleTranslationResolver` asks for generation on a cache miss and polls the cache
  on a bounded schedule again (250 ms → 6 s, 7 polls), mirroring the chat path: cloud first, Apple
  Translation only when generation times out or fails. `generateOnMiss` is sent once; later polls read the
  cache only.
- Test hygiene: `Scripts/test.sh` and `Scripts/test-ui.sh` clear `Products/*.swiftmodule` copies that are
  older than their `PackageFrameworks` counterparts. Xcode copies package modules into `Products` for the app
  build while test builds compile the same targets as frameworks; `-I Products` wins during the test build,
  so a stale copy hides new public symbols (`cannot find type in scope`). App builds regenerate the copies.

## Verification

- `Scripts/test.sh -only-testing:LingoTripTests/BackendDictionaryExampleTranslationsTests
  -only-testing:LingoTripTests/DictExampleFallbackTests` → 7 passed, 0 failed: cache hit reads once, a miss
  requests generation exactly once, pending polls until ready with `generateOnMiss` true then false, polling
  is bounded, and the Apple fallback routing tests still pass.
- Simulated the stale-mirror defect by re-creating an old `BackendKit.swiftmodule` copy and running the test
  target: the scripted cleanup removed it and the run passed. A following `Scripts/preview.sh build` recreated
  the copy, so app builds are unaffected.
- Backend: `pnpm typecheck`, eslint and prettier on the touched files; the admin-console integration test now
  asserts both `translation` and `dictionary_example_translation` are managed routes (integration suite needs
  an isolated PostgreSQL/Redis, not run here).

## Open items

- Backend release with the restored `translation` route is still owed: the production host rejects this
  machine's SSH key, so the console keeps hiding `translation` until an operator deploys
  `Backend/build/lingotrip-backend-5c456da.tar.gz` (or a newer package) with
  `Backend/ops/native-server/deploy.sh`.
- Real provider latency/quality for generated example translations, and physical-device Apple fallback, need
  a live check once the release is deployed.
