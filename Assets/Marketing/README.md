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
