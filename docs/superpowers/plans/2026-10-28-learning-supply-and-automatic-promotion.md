# Learning Supply and Automatic Promotion Implementation Plan

> **For agentic workers:** Use superpowers:subagent-driven-development for independent backend, iOS and authoring tasks. Continue without intermediate approval; the owner approved the supply recommendation and automatic promotion.

**Goal:** Expand towards 180 complete practices at each of the 15 supported learning levels (90 days at two practices/day), and advance to the next level automatically when the current level earns nine stars.

**Architecture:** PostgreSQL remains authoritative for rewards and profile changes. Automatic promotion reuses the domain profile gateway within the account learning transaction, preserves all historical answers/points and freezes active attempts to their original difficulty. Existing manual promotion snapshots remain readable. The app synchronizes the authoritative profile and shows the existing celebration without requiring special tests or a confirmation to advance. New content is explicitly authored, reviewed in complete groups, and published in bounded batches; content and code releases remain separately traceable.

**Tech Stack:** TypeScript/Fastify/PostgreSQL; SwiftUI; explicit JSON authoring with deterministic serialization and existing catalog validation.

## 1. Backend automatic promotion

- [ ] Add isolated regression cases around the real transaction: 539 stays, 540 advances once without a course, retries/concurrent commands do not advance twice, old answers and frozen attempts remain valid, already-full profiles catch up, highest level stops.
- [ ] Implement a small learning automatic-promotion repository/helper using `LearningContextReader.promotionProfile/promoteProfile`, with existing account locking and stable operation identity. Hook award and relevant inspect/start paths; never mutate the explicitly read-only repository path.
- [ ] Preserve earned points on their original level; no fabricated credit in the next level. Safely handle existing full levels in order, and keep legacy promotion read paths compatible.
- [ ] Run focused module/integration tests in a verified isolated database, typecheck, lint and architecture checks; inspect diff and commit explicit backend paths.

## 2. iOS automatic advancement

- [ ] Inspect the authoritative backend contract with the backend implementer. Add hosted model cases for a reward return that changes level, profile synchronization, highest-level completion and failed refresh recovery.
- [ ] Update the real learning page/model to recognize automatic advancement and reuse the promotion celebration as acknowledgement only; remove the prerequisite special-test/manual promotion action from the normal path. Preserve the ninth-star landing, current next-star point label and old history.
- [ ] Run focused hosted tests and standard/compact real-page previews. Install the latest build with `Scripts/preview.sh`; retain visual evidence and commit explicit paths.

## 3. Supply expansion campaign

- [ ] Freeze the baseline from `build/learning-supply-audit-20261028/local-report.json` and production acceptance `docs/verification/practice-directions-20261026.json`: 1,418 complete practices / 11,871 responses; 180 practices per supported level requires 1,282 more groups, approximately 9,438 responses at current group sizes.
- [ ] Prioritize CET4/CET6, primary1–primary4, advanced, primary5–primary6, then junior/senior reserves. Track each level and task-family separately. Kindergarten is outside this approved 15-level supply target.
- [ ] Author entirely new complete passages/tasks and explicit questions, keys, distractor explanations and bounded acceptable variants. No mass name/number substitutions; no subjective tasks; no unreviewed or missing-media listening/image tasks. Preserve the existing immutable catalogs and source evidence.
- [ ] Add a separate 2026-10-28 run with deterministic compilation, explicit source-format bindings and incremental validation. Admission and rollback must cover the new namespace, including senior task rules; do not silently reuse the 10-24 publication identity.
- [ ] Review each authored batch, compare identities/materials against existing supply, run structural and grading checks, retain declared review limits, and commit completed batches separately.
- [ ] Publish verified batches with the existing bounded maintenance workflow once secure SSH access is restored. Never count offline candidates as online supply. Reconcile aggregate counts after each release without creating real-user attempts or hashing the whole old corpus.

## 4. Release and reporting

- [ ] Restore the known secure deployment connection without printing credentials. Existing `ssh root@120.25.204.159` rejected authentication during the prior read-only audit; credentials are a publication dependency, not a reason to stop local implementation/authoring.
- [ ] Deploy verified backend changes under standing owner authorization, retain rollback artifacts and data, verify affected online behavior, and publish only approved content batches.
- [ ] Record exact authored / checked / published group and response counts separately, current target gaps, automatic-promotion evidence, remaining blockers, commit IDs and simulator preview.
