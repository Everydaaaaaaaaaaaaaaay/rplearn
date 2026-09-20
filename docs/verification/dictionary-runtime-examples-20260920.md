# Runtime dictionary example completion — 2026-09-20

## Scope

Extend top-5000 seeding with on-demand completion for recognized remaining words.
Zero relevant examples adds two, one adds one, two or more does not generate.
Persist English sentences, Chinese translations and contextual glosses in PostgreSQL
for cross-user reuse. Preserve original dictionary rows and historical migrations.

## Verification

- Backend: 26 focused unit/integration tests passed, including concurrent actors,
  baseline eligibility, retry/cooldown, retained results after job cleanup, strict
  route inputs and blocked-user quota isolation. Database tests used isolated local
  PostgreSQL on port 55439 and Redis on 56389.
- TypeScript, focused ESLint and dependency architecture checks passed.
- iOS: 42 Xcode-hosted tests passed, including 5,000-word coverage and client polling.
  Result: `build/DerivedData/VerificationResults/20260920T060618Z-72252.xcresult`.
- Real backend UI test `DictionaryExampleFlowTests/testRuntimeExamplesAndSharedReuse`
  passed. Murmuration received two translated examples; closing/reopening reused
  identical content. Result:
  `build/DerivedData/VerificationResults/20260920T061417Z-74173.xcresult`.
- Two authenticated guest actors sent 12 concurrent resolve requests per word.
  Serendipity added two, unflappable added one; both actors saw identical results.
  Unknown `xqznotawordzz` remained unavailable. Production database confirmed exactly
  one job and one attempt each for serendipity, unflappable and murmuration.
- Full authoritative baseline import: 761,380 entries. Source SHA-256:
  `4ed49edf9b2beaedaf1b57060425195195966ebfdad61af69066be57cdc779ba`.

## Operational boundaries

Migration 0025 adds data; it does not delete user data. Job deletion sets its reference
to null while keeping generated content. Failures have three attempts and one-hour
cooldown; dead/missing jobs become retryable rather than permanently pending.
Model validation is structural and relevance-focused, not human semantic certification.
The App needs one update for the new trigger; subsequent results are live/shared.
This task does not publish an App Store/TestFlight build.

## Release

Production release `20260920-learner-runtime-v2` activated successfully. Post-deploy
concurrent resolve/reuse checks passed; all three verification words still had one
job and one attempt. Prior release `20260920-learner-runtime-v1` remains available
for rollback. Latest Debug App installed and launched in the existing iPhone 17 Pro
simulator using `Scripts/preview.sh preview home`.
