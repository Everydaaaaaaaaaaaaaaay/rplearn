# 池畔观察 / Pond study

## Provenance and use

- Stock film: **Tree reflected in a pond**, Mixkit item 1202, contributor
  `rubenvelasco`: https://mixkit.co/free-stock-video/tree-reflected-in-a-pond-1202/
- Download: https://assets.mixkit.co/videos/1202/1202-720.mp4
- Checked 2026-09-06: item explicitly carries the **Stock Video Free License**,
  permitting commercial / educational projects, modification and distribution;
  attribution optional. License: https://mixkit.co/license/modal/videoFree/ ;
  https://mixkit.co/license/ ; limits: https://mixkit.co/terms/ .
- Embedded only as part of the app's composed learning scene, not a stock-asset
  download, resale or competing media library. No claim of local live footage.
- Source SHA-256: `66b874115622995a880bc0e4f26912d11e181d9221205fb37ccd20eb7568a7e7`.
- Rejected candidates 21130 and 20261 carried Restricted / personal-only terms;
  neither is included.

## One-shot foreground

`foreground-source.png` is the unmodified, first-and-only generated master
(852 × 1847). Exact generation request is the three prose paragraphs in
`foreground-prompt.md`; the following reference links document real-object
research. Inspected actual binocular and sketchbook photos for physical structure.
Those third-party reference photographs are not included in the app or repository.

Master SHA-256: `4e782c8db50953de85ab17699f00ebf3385de7afdf4da0776ac1febe3a8650f2`.
The actual generated ledge begins at y=848 (not the suggested y=58%); production
calibration follows the actual photo. Only its opaque lower rectangle is used.
No AI cleanup, second generation, texture repaint or inpainting was performed.

## Deterministic preparation

Run `bash Scripts/prepare-pond-activity-scene.sh <downloaded-1202.mp4> Assets/Activities/Pond/foreground-source.png`.

- Film cropped to source `(68,0,584,584)`: excludes the fish and stone edge
  throughout the inspected sequence. Physical footage retained at native detail;
  no wasteful pre-upscale before decoding on the device.
- 24 fps, silent H.264, 18 seconds, about 9.1 MiB. Complex ripples need more bitrate
  than the park's mostly static background. No new runtime library or server.
- Forward-only two-second environmental crossfade moves source 18–20 into 0–2;
  playback starts at source 2, so file end/start are adjacent original frames.
  No reversed water, disappearing person/fish or frozen action.
- AVPlayerLooper queues the next cycle without a notification-seek pause.
- Poster is extracted from the final encoded video, not a different photo.
- Seam frame SSIM 0.718; adjacent first/second-frame SSIM 0.716. This is a
  continuity comparison for moving detailed water, not a claim that looping is
  mathematically invisible. Contact-sheet review covers the blend region.

## Objects and interaction

- Binoculars → 细看倒影: language for reflections and apparent movement.
- Sketchbook → 构思速写: choose a subject and compositional intent, no fake drawing.
- Postcard → 写张短笺: assemble a private two-line note, never send it externally.

Object quads live in `ActivitySceneGeometry.swift`, all on the 852 × 1847 canvas.
Typography, ivory glow, shadow and press feedback reuse the same shared components
as Home/My and the accepted park scene. Real video and foreground share a fixed
coordinate space; the tab bar overlays them rather than resizing either layer.

Playback pauses when covered, off-tab, inactive, low-power, thermally constrained
or Reduce Motion is enabled. Scene switches replace the decoder; no hidden
carousel of continuously playing videos is retained.
