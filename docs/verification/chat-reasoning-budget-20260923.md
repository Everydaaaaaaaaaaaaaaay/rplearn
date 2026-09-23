# Chat reasoning-only empty responses — 2026-09-23

## Evidence

The two reported conversation failures at 12:39:42 and 12:40:10 (+08)
consumed exactly 512 output tokens each. OpenRouter generation inspection
confirmed `finish_reason=length`, `native_finish_reason=length`, and
`native_tokens_reasoning=512` for both. No visible text was produced.
The subsequent coach_review succeeded. This establishes output exhaustion,
not evidence that the learning toggle corrupts the conversation request.

## Change

GLM conversation output budget floor is 2048, still capped by the configured
route limit (currently 2400). Short-answer prompt constraints are unchanged.
This increases available reasoning headroom, not a fixed billed token amount.
OpenRouter streaming retains the finish reason and reports AI_OUTPUT_LIMIT for
reasoning-only exhaustion after yielding usage, preserving settlement data.
No unbounded or additional automatic paid retries were introduced.

## Verification

- AI provider regression suite: 22 passed; includes reasoning-only SSE with
  final usage, no successful done event and no reasoning text disclosure.
- Full default backend suite: 164 passed, 78 integration/environment tests skipped.
- TypeScript check, architecture check and focused ESLint passed.
- Repository-wide ESLint remains blocked by pre-existing errors in ignored
  build/bulk-console-preview.ts and test/unit/encounter-weights.test.ts.
- Six authored direct-provider scenarios returned nonempty text and stop.
- Native release 20260923-chat-reasoning-budget activated; readiness passed.
- Three post-deployment production AI-service streams using a dedicated test
  principal and authored multi-turn music context succeeded with maxOutputTokens
  requested as 120. All yielded text, usage and done; outputs were 38/38/39 tokens.
- Anonymous HTTP access correctly rejected the probe (401); service verification
  used the production service assembly instead, without changing authentication.

## Limits

The user's exact private conversation was not replayed and the phone UI toggle
was not exercised in this pass. A finite output cap cannot guarantee every future
upstream request succeeds. This fix addresses the verified 512-token failure and
correctly identifies future reasoning-only exhaustion rather than mislabeling it.
