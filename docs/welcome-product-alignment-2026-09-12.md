# Welcome concepts aligned with the product · 2026-09-12

Keep the conceptual composition and existing welcome backdrop; remove invented UI/features.

- Activity preview uses the actual tab names/order/icons: 信息、联系人、活动、我的,
  plus 测试 in Debug only. Activity is selected. The scene remains a conceptual illustration.
- Chat uses production `ChatTitleView`, `MessageBubble` and `AvatarBadge`; idle composer
  matches ChatComposerSection. Remove the fictional memory-status chip.
- Dictionary preview uses the same chat setting and the production `DictCardView`, backed
  by the bundled dictionary and grammar store. A presentation-only height parameter keeps
  the card within the smaller canvas; default height remains 340 for existing callers.
  No AI or Apple Translation request is made. Demo example translations are local literals;
  preview controls do not send messages, record audio or change favorites.
- Extract `StarterPortraitCard` from actual starter selection and reuse it in welcome, with
  a compact layout. Read Oliver from `main_characters.json`; remove the fictional difficulty,
  speaking assistance, dynamic adjustment controls and the claim that every choice is editable.
- Feature boundaries remain intact: Onboarding does not import ChatFeature or HomeFeature.
  Composition root injects existing dictionary/grammar dependencies.

Verification results and installation status are recorded after the final visual checks.

## Verification

- iPhone 17 Pro: welcome navigation/auth handoff, all starter portraits after extraction,
  and four-page light/dark captures passed (`20260912T030529Z-85930.xcresult`).
- Strengthened welcome checks passed: actual tabs, loaded dictionary word and chat sentence,
  actual starter avatar, absence of all three fictional settings (`20260912T031043Z-87857.xcresult`).
- iPhone SE: accessibility text navigation passed. Initial screenshots exposed clipping in
  the compact dictionary and starter card. Added height-aware canvas scaling and shortened
  compact profile text using clauses from the real catalog. Final four-page light/dark checks
  passed (`20260912T031218Z-88651.xcresult`); inspected dictionary sentence/card and starter
  title/card/button for full visibility. Full selection card layout is unchanged.
- Final signed iPhone build passed. No backend changes or deployment needed.

Bundles: `/tmp/lingotrip-grammar-derived-20260911/VerificationResults/`.
Final compact captures: `/tmp/welcome-real-final-images/`.

## Virtual companion presentation correction

Welcome and promotional examples must describe AI conversation and in-app stories without implying real-world meetings or physical contact with NPCs. Ruby's sample now recalls the user's presentation nerves; the dictionary example asks about personality instead of inviting a trip.

The final welcome illustration is a static Oliver profile preview. Removed its decorative paging dots and fake travel button. The functional four-page welcome indicator remains. Actual three-way starter selection occurs after the opening group-chat story, as reflected in the welcome description.
