# Marketing screenshots — 2026-09-15

Nine unretouched screenshots captured from the actual Debug app on the owner's iPhone 13, 1170 × 2532 pixels. The final set is at `/Users/tiantian/Pictures/LingoTrip-Promo-20260915/final/`; the sibling ZIP contains exactly these nine originals. `screenshots-20260915.json` records their SHA-256 hashes. The contact sheet is a resized overview only.

| File | Purpose |
| --- | --- |
| 01-messages | Six distinct NPCs, balanced avatar colors and varied conversation topics |
| 02-chat | Natural Ruby conversation, with no implied physical meeting |
| 03-dictionary | In-context word lookup and bilingual examples |
| 04-companion | Ruby's personality, interests and fictional companion identity |
| 05-city | Immersive London navigation |
| 06-activities | Actual animated park scene and activity hotspots |
| 07-encounter | Victor's bundled authored encounter with both choices visible |
| 08-story | Oliver story artwork and branching dialogue |
| 09-favorites | Saved words and a bilingual sentence |

## Reproduce

Build and install the Debug app, then run:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer python3 Assets/Marketing/capture.py DEVICE_ID OUTPUT_DIRECTORY
```

Use `--scene 01-messages` to capture one scene, or `--simulator` for review only. Phone captures use `devicectl device capture screenshot`. The phone must be unlocked. The script restores a normal app launch afterward.

The explicit DEBUG marketing flag runs inside the existing in-memory UI-test workspace. Conversations, favorites, coins and story progress are prepared demonstration data; session restoration and background refresh are bypassed, and the backend URL points to an unused local port. No live AI calls or real account writes are needed. UI comes from the actual feature views, not composited mockups. Encounter text and characters come from the bundled authored catalog. Additional avatar resources are copies of accepted catalog artwork: Victor from `Assets/NPC/Library/v3/images/npc-0010.png`, Mabel from `expression-jade-laugh-bg-v2.png` in the same folder.

## Verification

- All nine physical-device captures visually reviewed; favorites reduced to two words so the sentence remains fully visible.
- Signed device Debug build passed and installed; avatar tests: 6 passed, 0 failures (see `avatars-20260915.md`).
- Capture script syntax and Git whitespace checks passed.
- The attempted world-map screenshot was rejected because globe city annotations were incorrectly positioned and overlapping. It is excluded from the final set; that existing map issue needs a separate fix.
- Starter avatar generation, reference provenance and palette corrections are recorded in `avatars-20260915.md` and `avatar-prompts.json`.

## Updated physical-device set — 2026-09-15 v2

- Built source commit `edb6723` in signed device Debug configuration; build succeeded and installation on the owner's iPhone 13 succeeded. Includes encounter redesign, welcome presence window and chat reply recovery.
- Recaptured all nine scenes from the phone, with the same isolated in-memory demonstration workspace. Normal app launch restored successfully afterward.
- Originals: `/Users/tiantian/Pictures/LingoTrip-Promo-20260915-v2/final/`; ZIP: sibling `LingoTrip-Promo-20260915-v2.zip` (exactly nine originals); resized review overview: `overview.jpg`.
- All nine images visually inspected. Message list has six varied NPCs and balanced palettes; dictionary examples and saved sentence are visible. Encounter now showcases the English title, character identity, scene backdrop and continuous narrative; its choices are below the captured viewport. Story screenshot shows both branching choices.
- Each original is 1170 × 2532; unique SHA-256 hashes recorded in `screenshots-20260915-v2.json`. ZIP integrity and entry count verified. Original v1 retained.
- No source UI/assets changed in this capture task. Prior scene-motion acceptance limitations remain unchanged; screenshots verify these captured frames only.

## Native reply motion capture — 2026-09-15

The additional `UI_TEST_MARKETING_MOTION=1` flag omits Ruby's last prepared reply. Only the app's fixed in-memory UI workspace may enable `ChatDependencies.marketingMotionCapture`; it also requires the existing marketing and authentication-bypass flags. The native chat view then shows its actual typing indicator and delivers two prepared reply parts through `deliverAssistantReply`, `RoleplayReplyFormatter` and `RoleplayTypingPace`. No online model, review or relationship request is launched by this playback. Release builds omit the playback and dependency flag.

A new signed iPhone 13 Debug build and the simulator Debug build passed. The phone installed successfully. This phone reports CoreDevice Screen Recording unsupported, so the promotional reply recording uses the iPhone 17 Pro simulator. A new Singapore home screenshot was captured from the physical iPhone; normal phone launch was restored. Source and reproducible capture commands live in `Tools/coovingo-film/`; raw takes live in `/Users/tiantian/Movies/Coovingo-Promo-20260915/raw/`. Recording end-state and native screenshots were inspected, and the iOS architecture check passed. Computer Use Device Hub remained unavailable (error -10005); no Computer Use interaction success is claimed.
