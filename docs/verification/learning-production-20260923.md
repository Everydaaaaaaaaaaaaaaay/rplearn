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

## Continuation rounds (17:20 local)

- The phone was unlocked and online. The opt-in live UI test first skipped because the setting was absent from the test bundle, then because `Bundle.main` referred to the runner and `YES` was a Boolean. The test now reads its own generated Info.plist and requires explicit opt-in. Skipped results `learning-phone-round3/4/5-20260923.xcresult` are not passes.
- Round 6 entered real chat and started a practice, but `isHittable` reported false for a visibly displayed “知道了” button. A center-coordinate tap worked in round 7. The visual and accessibility tree are saved in `/tmp/learning-round6-attachments/`; actual VoiceOver behavior is still unverified.
- Round 7 technically passed, but inspection rejected it as acceptance evidence: the script ended a travel practice, started a dinner practice, then sent a hardcoded park answer. At the 60-second snapshot there was no confirmed NPC reply or reward. The test now preserves an existing practice, checks the actual task prompt before sending, and requires an incoming Ruby bubble plus completed learning result.
- Round 8 (`build/learning-phone-round8-20260923.xcresult`) exercised ordinary chat with the displayed dinner task. Three natural-paced messages were sent, Ruby replied, the practice ended, the card showed independent evidence and the details showed **10 XP**. The saved local state has two evidence items: the earlier mismatched dinner task scored `[1,2,2,2]` with no reward, and the aligned dinner answer scored `[2,2,2,2]` with one reward. The successful round took about 227 seconds, so the cause of the long wait still needs investigation. The NPC called the answer “pasted homework”; a friend-style instruction adjustment is implemented.
- The real signed-in phone's independent reviewer sample completed 8/8 expected outcomes with HTTP reachability and no errors (`/tmp/learning-live-round10.json`). These samples do not change the learner ledger and do not replace touch E2E.
- The physical draft → details → project TTS playback → exit → return path passed (`build/learning-phone-listening-round1-20260923.xcresult`). The unsent draft was intact on return and the test removed its temporary draft. Options remained disabled while playback had not completed. This does not yet verify a full listening submission or interruption recovery after a completed play.
- Focused Xcode-hosted learning tests after the prompt change: **24 passed, 0 failed, 0 skipped**, result `build/DerivedData/VerificationResults/20260923T091649Z-88865.xcresult`.
- An isolated real ChatViewModel run on the phone after the wording change completed every step (`/tmp/learning-flow-round12.json`): greeting kept the practice open; a later park choice received a natural reply without homework/test framing; independent evidence persisted and restored exactly. Its reply timings were 16.4 and 17.7 seconds. The first attempt exposed a race in the evaluation harness, which checked and paused while its idle-triggered review was still running; the harness now waits for the review to settle. This isolated run is supplemental to physical touch testing.
- The real account has reached today's **12/12 review request cap**. Keep queued attempts and prior results; do not reset limits to manufacture another successful round. Continue other routes and resume account-scored tests after UTC rollover.
- Full real-model calibration found three initial false judgments among 47 selected-task cases: a tautological reason passed, an unrelated future plan passed as reflection, and a clear question about time was marked incomplete. The explicit-task prompt had omitted the skill rubric. Including it and clarifying those semantics fixed the three; one complete-suite rerun then exposed a regression on “The park because it is close,” which lacked a choice verb. The final prompt explicitly accepts that meaningful fragment. **Final selected-task run: 47/47 expected outcomes, no errors** (`/tmp/learning-live-all-edges-final-r2.json`).
- In 31 ordinary observation samples, “I took my English test this morning. The last question was about animals” was first scored against a partially satisfied higher band instead of its fully supported basic band. The no-task instruction now selects the highest fully supported band. **Final observation run: 31/31 expected outcomes, no errors** (`/tmp/learning-live-observation-final-r2.json`). Expected skill sets and paused flags also matched across both final reports. These are finite sampled judgments, not general accuracy or CEFR certification.
- Active practice previously skipped its 12-second quiet window when a burst reached the ordinary four-message batch threshold. The queue now preserves the quiet window for a selected task while ordinary four-message observation remains immediate. A focused regression covers the difference.
- Final integrated Xcode-hosted suite after these changes: **93 passed, 0 failed, 0 skipped**, result `build/DerivedData/VerificationResults/20260923T094552Z-95064.xcresult`.
- Final Release simulator build completed with `Scripts/build.sh -configuration Release` (`/tmp/learning-release-continuation-final.log`); `Scripts/preview.sh preview messages` installed and opened the latest Debug simulator app (`/tmp/learning-preview-continuation-final.log`). The latest Debug build was also installed on the physical iPhone without clearing its app data.
- A second physical listening round completed both allowed Supertonic-3 plays for the first item, unlocked choices only after full playback, and kept the 2/2 count when reopening without submitting an answer (`build/learning-phone-listening-round3-20260923.xcresult`). The first attempt at this harness reached full playback but failed on `nil` versus empty draft comparison; the draft was not lost. Screenshot inspection found that unlocked answers looked nearly identical to locked ones. The options now gain a teal fill and border when enabled, and the instruction changes to “现在可以选择答案”; the visual rerun passed (`build/learning-phone-listening-round4-20260923.xcresult`, `/tmp/learning-listening-round4-attachments/`). No listening score was created.
- Post-visual final integrated suite: **93 passed, 0 failed, 0 skipped**, `build/DerivedData/VerificationResults/20260923T095908Z-97443.xcresult`. Release simulator build and the required Debug simulator preview were repeated after the listening-style edit (`/tmp/learning-release-postvisual.log`, `/tmp/learning-preview-postvisual.log`).

Remaining: confirm the new NPC wording and four-message quiet window in physical touch chat after the account cap resets; check restart/cloud persistence and main-chat timing; expand physical interaction and quantitative cases, full listening playback/submission, offline recovery and account isolation. A finite set of passing checks is not final release acceptance.
