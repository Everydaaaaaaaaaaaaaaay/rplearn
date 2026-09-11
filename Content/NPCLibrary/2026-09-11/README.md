# Preauthored 200-person library — in progress

The approved ten-person pilot is the editorial quality reference. This directory currently fixes **bindings and coverage**, not 200 completed or released characters.

`briefs.draft.json` contains the completed planning pass, **not approved content**. `plan-review.json` records a truncated global review and independently observed repeated templates. Correct the substantive niches before expanding stories. Original responses and all paid receipts remain in the private experiment directory. Generation requires an editorial approval record covering the hash and all IDs of the revised briefs; this is an internal quality gate, not another user permission request.

`slots.json` assigns all 200 accepted v3 avatars exactly once. Age range, creative gender and appearance come from `observed` metadata and verified image hashes. These constrain compatibility only; occupation, nationality, personality, history and interests are planned independently. Ten approved pilot briefs retain their identities. The pilot's `park-map` action is normalized to the app's actual `park-route` ID when imported; source pilot files remain unchanged.

Coverage: all 15 cities × 9 actual scene actions, with 13–14 people per city. Scenes preserve the user's selected action, including sharing existing pastries rather than moving the scene to a shop counter. A single scenario per person is initial coverage, not evidence of a rich repeat-encounter library.

## Reachability acceptance requirement

Every one of the 200 identities must be reachable through at least one **currently available** city/action, not only future content. Current assignment has 1–2 people per city/action. Release checks must enumerate the final imported roster and the real selection predicates; coverage in this planning file alone is insufficient.

Scene fit and recent encounters may change relative weights. Age, occupation, interests and personality must not become exclusion filters. Normalize a meaningful exploration component across the eligible pool so repeated encounters cannot push anyone arbitrarily close to zero. Verify both a mathematical minimum probability and deterministic sampling under extreme recency histories. The bound is conditional on choosing the applicable city/action and on an outing yielding a person; it does not guarantee an encounter after a fixed number of outings. Honor user-removed contacts and actual city access rules. No unchosen first-meeting plot should be replayed as new history for an existing friend.

## Replacement decision

The user authorized replacing the old generated encounter roster and releasing its avatar allocation. The new library is authoritative after validation and atomic activation. Ruby is the existing main companion and must remain intact. No database deletion is needed. No production mutation has occurred for this library yet.

## Private generation

`Tools/ContentPipeline/npc-library.mjs slots.json /private/output plan` plans remaining identities in batches. The revised planner receives no images, appearance descriptions or scenes. Including prior briefs did not prevent copying: the current draft is explicitly rejected pending editorial revision. `audit-plan` retains a separate global review receipt; a truncated review is not accepted as a successful audit. Inspect and correct the global plan before running `generate`; generated stories remain drafts until semantic review. No phase publishes or accesses the application database.

The shared ledger caps planning, generation and subsequent review at **CNY 25**, USD/CNY 7.2. Provider ceilings are $0.20/M input and $0.60/M output, GLM 5.3 Flash with minimal reasoning. Each dispatched request has a durable key; unknown-cost requests retain their upper estimate and are never automatically redispatched. A process lock prevents simultaneous writers. After an interrupted process, reconcile receipts and verify the process is stopped before removing its lock. This cap is provider spend, not Codex usage or user app credits.

Verification:

```sh
node Tools/ContentPipeline/verify-npc-library.mjs
node --test Tools/ContentPipeline/library-provider.test.mjs
```

Backend groundwork: `authored-library-repository.ts` validates a full import and writes identities and scene coverage in one transaction. It is CLI-only and has not imported the draft roster. Actual database import/idempotency/rollback verification remains required. Selection now mixes a 40% uniform exploration component with the existing soft weights. Unit tests cover the conditional probability floor at 1, 2, 14 and 200 candidates and a deterministic 100,000-draw sweep; the existing isolated encounter integration tests pass. These tests do not certify future app reachability or completed story content.

Still required before release: full narrative generation, semantic review and repairs, global similarity audit, immutable import and atomic roster activation, local branch playback, no-live-LLM tests, app/backend verification, deployment and phone installation. Structural validity or a successful API response is not editorial approval.
