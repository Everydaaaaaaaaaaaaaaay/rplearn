# Verification — 2026-09-15

## Native capture

- Capture fixture commit: `b53a165`. Simulator and signed iPhone 13 Debug builds passed; iOS architecture check and Git whitespace check passed.
- Physical iPhone 13 installation succeeded; fresh Singapore home screenshot visually reviewed, 1170×2532. Normal phone launch restored.
- Physical phone CoreDevice recording returned error 1001 / Screen Recording unsupported. Device Hub Computer Use returned -10005. Neither is counted as a successful recording or interaction check.
- Native motion take 2: iPhone 17 Pro simulator, 1206×2622, variable frame rate. The complete prepared two-bubble reply is present in the recorded end frame and the separate screenshot.
- Active typing/delivery timings are not sped up or slowed down. A 60fps transcode preserves source presentation time. The completed static end frame is held for two editorial seconds because simctl stops emitting frames when the UI is idle; no animated person or background is frozen to extend a loop.
- Video and screenshots exercise actual SwiftUI views. Dialogue is prepared demonstration data, not a measurement of live-model response speed.
- Latest simulator build installed again via `Scripts/preview.sh preview messages` after capture and left available.

## Picture and motion

- Seven scene layouts checked at render resolution or 50% review scale. Revised overlapping opening footer, partially clipped chat crop, and story framing; story now separates the visible character and complete choice card.
- Animation uses deterministic frame-based interpolation, monotone cubic-bezier easing, 24-frame crossfades and no CSS time animations or random motion. Product footage uses playbackRate 1.
- Native screenshots stay unretouched: device presentation and detail crops occur in the composition, without inventing app controls.
- Studio opens, resolves the composition and reports no error overlay. In-app browser playback state did not demonstrate advancing frames, so it is not represented as proof of continuous audiovisual viewing.
- No unverified activity background videos or defective world-map screenshots are included. Existing static encounter/story screenshot evidence is reused; this does not close the source scene-loop acceptance issues.

## Source checks

- `npm run lint` (ESLint + TypeScript): passed.
- Python capture/preparation scripts compile.
- Copied source hashes checked against the original screenshot manifest and `assets.json`. Raw additional sources are identified by `capture-manifest.json`.
- Music source and CC BY 4.0 requirement verified from the official Incompetech catalog/license generator; full attribution is embedded in the ending and in CREDITS.md.

## Final file

- Export: `coovingo-44s.mp4`, H.264, 1080×1920, 60/1 fps, exactly 2,640 video frames (44.000 seconds). AAC stereo 48kHz. Container duration 44.053 seconds including AAC padding.
- Size: 19668990 bytes; SHA-256: `d1898229e101934832d613707207c9834cc793c27fc24d452eab940f4a0fd5e3`.
- Complete FFmpeg video/audio decode: passed, empty error log.
- Final integrated loudness: -18.21 LUFS; true peak -4.57 dBTP; loudness range 1.70 LU. No clipping; opening/ending fades included.
- Final encoded-frame review: 12 selected frames cover intro, profile, active typing, first bubble, completed two-bubble reply, city/encounter, full story choices, dictionary, favorites and ending. Both reply parts and both story options are visibly present. Contact sheet is in the delivery directory.
- Screenshot/source SHA verification passed. Original physical screenshots were not altered.
- Full continuous perceptual audiovisual review by a human is not claimed; verification combines source-timing inspection, native end-state evidence, encoded-frame visual review and full technical decode.
