# 2026-09-12-v3 release acceptance

Resource: `App/Resources/npc-library-v3.json` (3,007,925 bytes).
SHA-256: `6927a16f2adabb8f75f40e90bf9a1276c0ff7502a0f1d667552b4c1502a4945c`.

- 200 exact-reviewed cards and 200 exact-reviewed stories; seven nodes / four paths per first meeting and one independent reunion per person.
- 23 final card candidate pairs and 32 story candidate pairs resolved against full, current records. Real overlaps were rewritten; explicit false-positive decisions bind both content hashes.
- All 19,900 card pairs and 19,900 story pairs lexically screened. Maximum token Jaccard: 0.1595 cards / 0.2528 stories. Shared eight-word passages: 7 cards / 412 stories, largely common scene openings. These numbers are screening evidence, not an assertion that prose shares no ordinary language.
- Avatar source check: 200 accepted hashes and compatible age/gender bindings, 135 current city/action slots. Isolated importer tests validate the final manifest against the actual backend schemas.
- Backend: `python3 Scripts/verify-backend-workflows.py --phase integration --test npc-authored.test.ts` — 2 passed; isolated PostgreSQL/Redis, no live AI. Evidence run `20260911T181830Z-d48feb2f`. Covers atomic import, immutable versions, failed-import rollback, prior friendship preservation, every character reachable, run replay and guest city restrictions.
- Hosted Swift: `Scripts/test.sh -only-testing:LingoTripTests/EncounterChapterTests -only-testing:LingoTripTests/SocialEncounterDiversityTests` — 3 passed, zero skipped. Evidence `20260911T181925Z-17945.xcresult`. Reads all 800 paths / 200 reunions, rejects malformed graphs, confirms local encounter playback without model generation.
- Provider admission tests: 3 passed, including durable receipts, unresolved-attempt protection and rejection of caps above CNY 35.
- Unchanged runtime UI evidence reused: 12 activity/encounter policy tests and 3 UI paths for Add Friend / Leave, chat handoff, lookup and voice playback from the integration commit.

The first attempted Swift command named package directories as test targets and did not run. The corrected hosted `LingoTripTests` invocation above passed. Xcode emitted dependency-scan warnings for DomainKit; no build or test failure remained.

Semantic uniqueness is an editorial judgment, not a mathematical guarantee. Cohort/index screening can miss subtle similarities; the final acceptance rejects identified substantive overlaps without banning ordinary shared human traits. See [production rollout](rollout.md) for the executed deployment, data-preservation verification and device installation status.
