# Encounter reading and reply recovery — 2026-09-15

## Scope

- Encounter views reuse the selected park/pond/rain cafe scene without entrance controls, with a frosted background and readable cards. Existing scene media are unchanged; original provenance and outstanding motion review remain in `Assets/Activities/RealMotion-v5/acceptance-v5.md`.
- English-first reading; one persistent translation switch toggles narrative, choices and title Chinese. `App/Resources/npc-encounter-titles-en.json` supplies offline editorial translations for all 200 first meetings and reunions. No model requests or runtime title-translation waits.
- Continuous transcript with automatic scrolling. Taps advance; choices are full-card buttons. Long-press a narrative word for lookup, while occupation words retain ordinary taps. Translation, speech and choice interactions must not advance the story accidentally.
- Per-character schedule boundaries vary by up to 12 minutes; daily rhythm shifts by up to one hour. Meeting time provides a stable 20–35 minute welcome window. Schedules rebuild identically after relaunch and respect local timezone.

## Reply diagnosis

Read-only production query for the reported period found both conversation requests at 13:02:41 succeeded, in 2,956 and 4,592 ms. A successful upstream response is not proof that iOS displayed it. The iOS interruption marker is written before streaming as crash recovery; a newly opened ChatViewModel previously treated that checkpoint as failure even while another page owned an active generation/delivery lease. The reopened page also lacked per-bubble notifications.

Recovery now follows the active producer, suppresses misleading retry state, reloads after the lease finishes and refreshes each delivered bubble. A cycle guard prevents the old observer from clearing a newer send. Genuine failed requests remain explicitly retryable; no extra paid generations are launched merely for reopening.

The extended two-day query found two `memory_summary / AI_OUTPUT_LIMIT` failures and one transient `coach_review / AI_UPSTREAM_UNAVAILABLE`. Memory requests previously used a 650-token cap without minimal GLM reasoning. The backend now uses minimal reasoning and a 1,536-token floor, still bounded by administrator route caps. Background retry counts remain unchanged.

## Production verification

- Backend unit tests: 8 passed; TypeScript and focused ESLint passed.
- Release `memory-budget-20260915` activated; previous `credit-rates-20260913` retained for rollback. Readiness returned `ready`.
- One synthetic memory probe using the deployed provider implementation and real provider returned valid JSON with 8 notes, `finishReason: stop`, 429 output tokens, USD 0.00015965. No user account data were written. This verifies the affected provider settings, not a new end-to-end account transaction.

## iOS verification

- Focused unit tests: 32 passed, zero failures/skips; `build/DerivedData/VerificationResults/20260915T061332Z-54871.xcresult`. Covers presence stability/welcome window, active reply ownership and observer cycle safety, and every authored encounter title.
- Final standard-screen UI tests: 2 passed, zero failures/skips; `build/DerivedData/VerificationResults/20260915T061747Z-56506.xcresult`. Covers translation without story advancement, full-card choice hit areas, transcript retention/auto-scroll, narrative lookup and speech control. The continuation gesture covers the scroll viewport including blank space.
- Small-screen UI test: 1 passed, zero failures/skips; `build/DerivedData/VerificationResults/20260915T061420Z-55632.xcresult`. Reviewed bilingual choice screenshot: both choices visible above tab bar, fixed controls readable. Small-screen run preceded the final viewport gesture placement; final standard tests passed after that change.
- Reviewed English opening, bilingual choices, and retained transcript screenshots from standard UI run `20260915T061154Z-54430.xcresult`; no entrance icons/text visible behind the frosted scene. Scene media unchanged; this does not close the original pending motion review.
- Latest Debug app installed with `Scripts/preview.sh preview home` on iPhone 17 Pro simulator `47DD7BF7-5378-47D7-ACC3-792EF8AAFF11`. No physical-phone or TestFlight installation claimed.

Device Hub Computer Use returned error -10005; focused Xcode UI automation and simulator screenshots are used for interaction and visual verification instead.
