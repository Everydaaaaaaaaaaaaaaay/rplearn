# Credits entry and backgrounds — 2026-09-13

- Home coin balance is static, without button traits or subscription navigation.
- “积分余额与明细” now appears directly after the subscription overview and pushes
  its own page. The previous purchase-heavy usage sheet has been removed.
- The credit page shows remaining/limit/used, reset time, recent charges and timestamps.
  Empty history is explicit. Missing credit data is not zero; network failures show
  a retry action before the migration archive. Billing explanations are collapsed.
- Apple renewal/cancellation and entitlement restoration are explicitly separate
  from credit balances and coins.
- Existing `/v1/access` and Swift DTO carry `credits` and `recent`; no server or balance
  mutations. The user screenshot shows subscription content, not a loaded credit page.
  Account-specific online loading has not been independently verified.

New backgrounds, prompts and source hashes:
[asset record](../Assets/Workbench/20260913-profile-subscription/README.md).

Verification: focused navigation test passed on iPhone 17 Pro and iPhone SE 3 in
`/tmp/credits-pages-final.xcresult`. Tests use an isolated unavailable backend and
verify profile/subscription navigation, static coins, credit page, retry and return.
Final screenshots reviewed at both sizes; titles and credit entry readable, no
horizontal clipping. These tests do not certify live account balances or checkout.
