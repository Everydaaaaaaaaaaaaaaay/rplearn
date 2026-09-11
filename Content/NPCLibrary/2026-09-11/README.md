# Preauthored 200-person library — in progress

The approved ten-person pilot is the editorial quality reference. This directory currently fixes **bindings and coverage**, not 200 completed or released characters.

The original `briefs.draft.json` is rejected historical planning, not release content. The revised fixed roster is `briefs.production.json`; individual cards are held in the private production directory with exact-content approval hashes. Repeated person-level mechanisms were replaced using the explicit directions under `directions/`. Global approval must be refreshed after the final edits.

All 200 story directions now have a source: 184 individually authored rows in `story-directions/batch-01.json` through `batch-10.json`, six prior reviewed plans in `accepted-six-plans.json`, and the ten accepted pilot chapters. `library-134.authored.json` and `library-160.authored.json` are directly authored complete chapters and reunions; `library-190.authored.json` completes and repairs an already returned draft. These avoid redispatching unresolved attempts. These sources are not a claim that all expanded stories have passed review. `editorial-story-repairs.json` records bounded, content-matched repairs; it is source/evidence, not the distributable manifest.

`slots.json` assigns all 200 accepted v3 avatars exactly once. Age range, creative gender and appearance come from `observed` metadata and verified image hashes. These constrain compatibility only; occupation, nationality, personality, history and interests are planned independently. Ten approved pilot briefs retain their identities. The pilot's `park-map` action is normalized to the app's actual `park-route` ID when imported; source pilot files remain unchanged.

Coverage: all 15 cities × 9 actual scene actions, with 13–14 people per city. Scenes preserve the user's selected action, including sharing existing pastries rather than moving the scene to a shop counter. A single scenario per person is initial coverage, not evidence of a rich repeat-encounter library.

## Reachability acceptance requirement

Every one of the 200 identities must be reachable through at least one **currently available** city/action, not only future content. Current assignment has 1–2 people per city/action. Release checks must enumerate the final imported roster and the real selection predicates; coverage in this planning file alone is insufficient.

Scene fit and recent encounters may change relative weights. Age, occupation, interests and personality must not become exclusion filters. Normalize a meaningful exploration component across the eligible pool so repeated encounters cannot push anyone arbitrarily close to zero. Verify both a mathematical minimum probability and deterministic sampling under extreme recency histories. The bound is conditional on choosing the applicable city/action and on an outing yielding a person; it does not guarantee an encounter after a fixed number of outings. Honor user-removed contacts and actual city access rules. No unchosen first-meeting plot should be replayed as new history for an existing friend.

## Replacement decision

The user authorized replacing the old generated encounter roster and releasing its avatar allocation. The new library is authoritative after validation and atomic activation. Ruby is the existing main companion and must remain intact. No database deletion is needed. No production mutation has occurred for this library yet.

## Private generation

Current workflow: author concrete scene-specific directions, apply them with `apply-editorial-story-directions.mjs`, expand with `npc-production.mjs generate`, then run its `review` phase. Every first-meeting chapter contains seven nodes and four paths; each person also has an independent short reunion. Targeted repairs preserve unaffected nodes and exact approved cards. Batched and nested model-generated story planning was rejected for branch logic and character drift; those experiments must not be used as approved sources.

`audit-npc-production.mjs` screens global character/story collisions, `adjudicate-npc-collisions.mjs` examines candidate pairs, and `npc-similarity.mjs` scans all 19,900 pairs for lexical overlap. Shared settings, normal politeness and broad hobbies do not by themselves establish a duplicate. Conversely, renamed objects do not make the same underlying scene different. Current global reports and every individual review are required by `build-npc-library.mjs`; a stale or unresolved report prevents assembly. No phase automatically publishes or writes to the application database.

The shared ledger caps planning, generation and subsequent review at **CNY 25**, USD/CNY 7.2. Provider ceilings are $0.20/M input and $0.60/M output, GLM 5.3 Flash with minimal reasoning. Each dispatched request has a durable key; unknown-cost requests retain their upper estimate and are never automatically redispatched. A process lock prevents simultaneous writers. After an interrupted process, reconcile receipts and verify the process is stopped before removing its lock. This cap is provider spend, not Codex usage or user app credits.

Verification:

```sh
node Tools/ContentPipeline/verify-npc-library.mjs
node --test Tools/ContentPipeline/library-provider.test.mjs
```

Backend groundwork: `authored-library-repository.ts` validates a full import and writes identities and scene coverage in one transaction. It is CLI-only and has not imported the draft roster. Actual database import/idempotency/rollback verification remains required. Selection now mixes a 40% uniform exploration component with the existing soft weights. Unit tests cover the conditional probability floor at 1, 2, 14 and 200 candidates and a deterministic 100,000-draw sweep; the existing isolated encounter integration tests pass. These tests do not certify future app reachability or completed story content.

Still required before release: full narrative generation, semantic review and repairs, global similarity audit, immutable import and atomic roster activation, local branch playback, no-live-LLM tests, app/backend verification, deployment and phone installation. Structural validity or a successful API response is not editorial approval.
