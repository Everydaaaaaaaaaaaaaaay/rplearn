# Welcome and opening story · 2026-09-12

This v1 record is superseded by [the v2 correction](welcome-onboarding-v2-2026-09-12.md).
It records the earlier implementation and its tests, not acceptance of the current release.

## Delivered behavior

- Welcome uses eight physical iPhone 13 screenshots (four screens × light/dark), replacing
  the manually constructed miniature interfaces. Product screenshots are rectangular crops,
  not generated compositions. Source hashes, crop rectangles and reproduction instructions:
  [capture record](../Assets/Welcome/README.md).
- Calm sky/coral gradients and static contour lines replace the nearly flat backdrop.
  No full-width footer material, top page fraction or swipe instructions. Graphical progress
  controls have 44 pt hit targets. Copy has distinct eyebrow/title/body sizes and more line spacing;
  vertical scrolling retains access on small displays and at accessibility text sizes.
- Opening is a local conversation with Gugu and Gaga and invitations from Oliver, Ruby and
  Marcus. Three choice moments, three options each; distinct follow-up conversations and an
  ending that recalls the first choice. All three companions remain freely selectable.
- Actual chat and opening share `ChatTitleView`, `MessageBubble` and `TappableText`/dictionary
  overlay. The scripted flow does not instantiate live roleplay services, call an AI provider,
  write narrative into ChatStore or claim pronunciation assessment.
- Settings → 重看旅程介绍 presents the welcome and story read-only, with a close button.
  It does not reset onboarding, learning profile, friendship or the selected city.

## Verification

- Hosted `OnboardingStoryTests`: all 27 choice combinations finish with the character-selection
  unlock; each introduces both guides and all three companions; all 27 transcripts differ and
  the ending recalls the chosen initial preference. Result:
  `/tmp/lingotrip-grammar-derived-20260911/VerificationResults/20260911T201459Z-40338.xcresult`.
- Opening UI plus existing ChatKeyboardTests: 2 passed, including actual three-option interactions
  and normal chat draft preservation after dismissing the keyboard:
  `20260911T201554Z-41138.xcresult`.
- Welcome UI suite: 8 passed (paging, login gating, accessibility text, portraits, selection
  success and retry, opening progression and appearance screenshots):
  `20260911T202625Z-43354.xcresult`.
- Introduction replay and updated welcome appearance checks: 2 passed:
  `20260911T202917Z-44085.xcresult`.
- Physical screenshot capture completed through devicectl, with isolated fixture data.
  The initial physical XCTest runner failed to bootstrap (exit 74); it is not counted as
  successful physical UI automation. Simulator captures were diagnostic only and are not
  the shipped image assets.

## Scope and preserved work

The existing activity photographic scene and motion assets are unchanged. This task evaluates
only the welcome's static crop/display; it does not change the motion acceptance status in
[the scene policy](activity-scene-visual-acceptance.md). No backend service deployment is needed.
Unrelated OpenRouter edits in `Backend/src/modules/ai/openrouter/client.ts` and its test remain
outside this commit. Capture fixtures are DEBUG-only; the normal launch restores the existing
signed-in account without clearing credentials. No uninstall or database reset was performed.

## Final acceptance and installation

- iPhone SE 3 simulator: latest crops, 44 pt indicators, both appearances and accessibility
  text checks passed (2 tests), `20260911T203045Z-44512.xcresult`. Inspected the stable page
  screenshots; images are centered and clipped to their own rounded bounds, text and bottom
  navigation remain readable. The capture test waits for page centering before attachment.
- Signed device build passed, log `/tmp/welcome-install-build.log`. Installed over the existing
  app via LAN; installation ID `B1881FD5-0D63-4673-8DDB-B2783209CE25`, bundle
  `com.tiantian.lingotrip`. No backend deployment or App Store submission in this UI-only task.
- Final physical welcome screen inspected at `/tmp/welcome-final-iphone.png`: actual activity
  screenshot, rounded crop, contour backdrop, centered copy and floating navigation all render
  correctly on iPhone 13. Relaunched with no fixture flags after capture.
