# Chat learning production acceptance — 2026-09-23

Status: implementation and real-device cycles in progress. Not a final release sign-off.

## Product contract

- Learning consent, receipts, optional practice and recovery live in ordinary chat.
- No forced quiz, fake NPC bubble, automatic paid practice initiation or accelerated reply rhythm.
- An optional details sheet is directly reachable from chat; contact-profile navigation is unnecessary.
- Learning reminders yield to composing and NPC replies, at most twice per UTC day with 10-minute spacing; deferral lasts 24 hours.
- A selected task is added to normal NPC context; normal chat and user burst timing remain unchanged.
- XP is participation, not language proficiency. No speech/pronunciation grading.
- Existing v1 local records are preserved; completed evidence/listening results sync by account.
- Pending source messages/unfinished practice remain device-local. Server revisions prevent blind overwrites; evidence deletion wins on merge and XP daily caps remain enforced.

## Findings and fixes

1. All learning UI/model wiring was Debug-only. Promote actual feature, retaining only evaluation harnesses behind Debug.
2. No inline consent, receipts or recommendations existed. Add compact expandable chat accessory and direct details/listening sheet.
3. Selected tasks never reached the normal NPC request. Inject explicit opt-in scene instructions without asking NPC to grade or repeat questions.
4. Account deactivation did not cancel learning tasks. Cancel and discard the account-bound model.
5. Existing phone state: 6 attempted batches, 10 calls, no evidence, 4 failed pending batches. Production logs show GLM output-limit failures and truncated JSON. Separate learning_review on DeepSeek non-thinking mode; keep evidence validation.
6. Failed attempts consumed the successful-batch cap. Separate successfulBatches from legacy attempted-batch counters; total request cap remains 12/day.
7. Active practice used 90-second ordinary idle timeout. Set 12 seconds after last learner message, still wait for the main reply owner to become idle. Ordinary observation retains 4-message/90-second batching.

## Completed checks

- Initial iOS chat integration: 36 tests passed (presentation and ChatWorkflowTests).
- Subsequent learning core: 58 tests passed, including cross-device merge rules.
- Release simulator build passed before the dedicated learning_review route was added; repeat required after final edits.
- Backend default suite: 166 passed, 79 environment-gated skipped.
- Isolated PostgreSQL migration/repository test passed: first save/read, account isolation, stale revision rejection, concurrent CAS, deletion cascade.
- Backend typecheck, focused lint and architecture passed.
- Production 20260923-learning-chat-v2 deployed with native readiness passing. New endpoint rejects anonymous access (401); learning_review route verified as deepseek-v4-flash, thinking disabled, 2400-token ceiling. No existing user rows or learning records were reset.

## Device workflow

User requested real-device adversarial testing with real providers. iPhone 13 is connected via USB. Device Hub Computer Use timed out; use explicitly opted-in XCTest on the real signed-in app and retain screenshots/AX attachments. No seeded replies, preview auth or speed override. The initial command used the unit-test scheme and was rejected before execution; corrected to LingoTripPerformanceTests. This is harness setup, not a product test pass.

## Pending gates

- Physical-device interaction rounds and image inspection; fix every observed failure and re-run affected paths.
- Listening interruption/return, keyboard and unsent draft preservation, repeated taps, assistance attribution, quota/offline/conflict UI.
- Final complete Swift tests and Release build after all changes; current simulator preview.
- Explicit final limitations: finite tests cannot prove absence of all bugs, and the proficiency thresholds are product heuristics, not validated CEFR certification.

## Continuation rounds (14:14 local)

- Final integrated hosted tests: **92 passed, 0 failed, 0 skipped**. Result `build/DerivedData/VerificationResults/20260923T061219Z-73627.xcresult`. Includes learning queue/presentation/ledger/reviewer and normal ChatWorkflow tests.
- Normal-size inline consent → practice → unsent draft → details → return → end → defer passed in the previous round (`20260923T060050Z-69716`).
- Maximum accessibility size: first run exposed offscreen actions; scrolling is required and tested. Image inspection then exposed oversized header symbols and wrapping action labels. Fixed symbols to 16/18pt, allowed two title lines, and stacked actions for accessibility sizes.
- Dark-mode test initially used an overridden launch preference and was actually light. Corrected to the app's appearance override. **True dark + largest accessibility size passed**, including consent, practice, draft preservation and deferral; screenshot inspected. Result `build/DerivedData/VerificationResults/20260923T061058Z-73109.xcresult`.
- Fresh learning results now precede daily-limit status in the header. Both direct-chat and details entry enforce the same daily-cap guard. Successful batch accounting uses completion date across midnight.
- Equal-date reward merge now chooses deterministically before applying the daily cap; reciprocal merge regression passes.
- Physical UI round 2 installed the updated app but again failed **before UI interactions**, with `Timed out while enabling automation mode`. Result `build/learning-phone-round2-20260923.xcresult`. This is a blocked gate, not a pass.
- Supplemental real-phone reviewer run selected 8 adversarial cases on the dedicated route. Network probe returned NSURLErrorDomain -1009; the first 3 requests returned -1005, triggering the harness's early stop. **No model accuracy result was obtained**. User asked to enable UI Automation and restore app network access. No grades or source conversations were reset.
- Live burst harness skips if an existing user draft would otherwise be sent accidentally.

Remaining: physical touch E2E, dedicated-provider accuracy regression, listening interruption and completion, offline/recovery receipts and long-session/account-switch validation. Do not present this record as final release acceptance.

- Final Release simulator build completed successfully after all runtime edits (`/tmp/learning-release-final.log`). Latest Debug preview installed with `Scripts/preview.sh preview messages`. Physical installation predates the final accessibility-only layout adjustments.
