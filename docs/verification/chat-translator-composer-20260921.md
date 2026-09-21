# Chat translator composer — 2026-09-21

## Behavior

- Normal composer remains one compact row (60 pt content with the 44 pt toggle hit area), plus the system bottom safe area. English text can grow for accessibility/long drafts.
- Translator reveals a compact mode capsule and source row above the same English draft. Source and English remain editable; opening/closing does not send or discard them.
- Gugu/Gaga circular windows and send circles are 30 pt visually. Speaker is in the source row; microphone remains in the bottom row. No source-row enclosing capsule or speaker background.
- Apple instant Chinese-to-English uses a dedicated system session, with 650 ms coalescing. No automatic AI fallback/charges. AI translation happens only on explicit action through the existing translation task/provider.
- Response revision and draft snapshot checks prevent cancelled/late responses overwriting edits. Failures retain drafts with inline retry. Only explicit Send sends English through the existing tutorial/quota pipeline.
- Chinese recording uses the existing recorder with zh_CN rather than changing the default en_US. Recordings used solely for transcription are deleted. Microphone/speech consent remains system-owned.

## Rendering and motion

- Blue normal / lavender translator background, with three shallow lit upper-rim layers (outer tint, broad highlight, inner rim). No border around the bottom safe area.
- Circular mask expands from the toggle position with an interruptible spring; shared controls stay in the same row. Inactive source controls have hit testing and editing disabled.
- One shared CMMotionManager, live device-motion gravity plus bounded acceleration. Requested update interval 1/15 s; low-pass smoothing and 200 ms visual interpolation, no fluid solver or endless display timer. Owner guards prevent a disappearing old view stopping the active view's sensor.
- Stops on disappearance, inactive scene and Reduce Motion. Reduce Motion switches to a short fade/static waterline. Unavailable sensors retain static rendering. Raw live device motion does not request Motion & Fitness activity-recognition authorization.
- Apple reference consulted: https://developer.apple.com/documentation/coremotion/cmmotionmanager

## Verification

- Architecture check and diff whitespace check passed.
- 13 focused unit tests passed: ComposerTranslationModelTests, TranslationServiceTests, VoiceRecorderTests.
  Result: `build/DerivedData/VerificationResults/20260921T072008Z-39237.xcresult`.
- UI checks cover normal/expanded layout, repeated toggling, retained Chinese source, and disabled hidden controls. Initial checks caught hidden-control state and a test tapping a dictionary word instead of dismissing the keyboard; both were corrected.
- Light and dark simulator screenshots inspected; dark border was softened to the top rim only, text uses explicit primary foreground, and palette uses fixed lavender instead of system magenta-purple.

## Remaining hardware validation

Simulator tests do not establish real-device frame rate, physical sensor response, Chinese microphone transcription, Apple language-pack availability or live model output. These require a physical device and are not claimed as verified here. No backend/schema changes or deployment were needed.

Final UI result: 1 passed, zero failures/skips:
`build/DerivedData/VerificationResults/20260921T073538Z-42952.xcresult`.
The scenario includes both Chinese and English drafts and repeated closing/reopening.
Chinese source input also reports composer activity to the existing NPC turn-taking policy.

`Scripts/preview.sh build contacts` completed successfully; latest Debug build installed
and launched on the existing iPhone 17 Pro simulator, left available for inspection.
