# Production rollout — 2026-09-12

Backend release `01bda3ce14e3` was activated through the native atomic deployment script. Migrations completed and `https://rplearn.haruyuki.cn/health/ready` returned `{"status":"ready"}`.

The CLI imported all 200 entries from the accepted `2026-09-12-v3` manifest. The installed server manifest SHA-256 matches release acceptance: `6927a16f2adabb8f75f40e90bf9a1276c0ff7502a0f1d667552b4c1502a4945c`.

Production verification:

- 200 characters, 200 unique enabled avatar bindings, no missing/disabled avatars.
- 15 cities × 9 actions = 135 populated slots, with 1–2 people each; conditional probability floor 0.20 under the selection policy.
- Before/after hashes and counts match for all existing content records, relationships and pre-existing NPC cards/traveler identifiers. Import preserved existing data, including the main companion.
- Published from a clean export of the committed backend. Unrelated uncommitted OpenRouter changes were excluded.

The signed iPhone app build succeeded and its bundled manifest matches the server hash. After the user unlocked the phone, CoreDevice established a **localNetwork / TCP** connection and successfully installed `com.tiantian.lingotrip` on the paired iPhone 13 on 2026-09-12. This was an in-place installation; no uninstall or device data reset was performed. The earlier connection error 4016 is resolved.
