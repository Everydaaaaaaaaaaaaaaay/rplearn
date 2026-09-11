# Preauthored 200-person library — in progress

The approved ten-person pilot is the editorial quality reference. This directory currently fixes **bindings and coverage**, not 200 completed or released characters.

`slots.json` assigns all 200 accepted v3 avatars exactly once. Age range, creative gender and appearance come from `observed` metadata and verified image hashes. These constrain compatibility only; occupation, nationality, personality, history and interests are planned independently. Ten approved pilot briefs retain their identities. The pilot's `park-map` action is normalized to the app's actual `park-route` ID when imported; source pilot files remain unchanged.

Coverage: all 15 cities × 9 actual scene actions, with 13–14 people per city. Scenes preserve the user's selected action, including sharing existing pastries rather than moving the scene to a shop counter. A single scenario per person is initial coverage, not evidence of a rich repeat-encounter library.

## Replacement decision

The user authorized replacing the old generated encounter roster and releasing its avatar allocation. The new library is authoritative after validation and atomic activation. Ruby is the existing main companion and must remain intact. No database deletion is needed. No production mutation has occurred for this library yet.

## Private generation

`Tools/ContentPipeline/npc-library.mjs slots.json /private/output plan` plans remaining identities in batches, with previous briefs included to discourage repeated niches. The planner receives no images or appearance descriptions. Inspect the global plan before running `generate`; generated stories remain drafts until semantic review. Neither command publishes or accesses the application database.

The shared ledger caps planning, generation and subsequent review at **CNY 25**, USD/CNY 7.2. Provider ceilings are $0.20/M input and $0.60/M output, GLM 5.3 Flash with minimal reasoning. Each dispatched request has a durable key; unknown-cost requests retain their upper estimate and are never automatically redispatched. A process lock prevents simultaneous writers. After an interrupted process, reconcile receipts and verify the process is stopped before removing its lock. This cap is provider spend, not Codex usage or user app credits.

Verification:

```sh
node Tools/ContentPipeline/verify-npc-library.mjs
node --test Tools/ContentPipeline/library-provider.test.mjs
```

Still required before release: full narrative generation, semantic review and repairs, global similarity audit, immutable import and atomic roster activation, local branch playback, no-live-LLM tests, app/backend verification, deployment and phone installation. Structural validity or a successful API response is not editorial approval.
