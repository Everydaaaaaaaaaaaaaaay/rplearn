# Activity scene visual pilot

Opt-in entry: Home → 城市活动 → 场景样板. The original activity page and its
business rules remain intact. This is a generic park vignette, explicitly not
presented as a photograph of the user's current city. Sparse passing movement,
not a claim to represent a crowded street. Phone visual/energy acceptance remains
the user's next evaluation; simulator results are not phone energy measurements.

## Sources and permitted use

- Video: stockyana / Mixkit item 4831, “View of a park while a girl runs across”.
  https://mixkit.co/free-stock-video/view-of-a-park-while-a-girl-runs-across-4831/
- Direct source: https://assets.mixkit.co/videos/4831/4831-720.mp4
- Source SHA256: `66a9efc3cd5f2f09d81207d6731f0297f95439a0711dd1f9a4ec128c9fb1bed6`
- Checked 2026-09-06: item is under **Mixkit Stock Video Free License**, not
  Restricted License. Permits commercial projects and modification. License:
  https://mixkit.co/license/#videoFree ; readable text:
  https://mixkit.co/license/modal/videoFree/ ; terms: https://mixkit.co/terms/ .
  No implied endorsement by the person depicted. Do not distribute as a standalone
  stock collection. No third-party footage was uploaded to another video service.
- Rejected items 25890 and 9261: their free versions are personal-use-only.
- Foreground: `table-source.png`, one built-in imagegen call. Input was the first
  frame of item 4831 as lighting reference only. Exact prompt: `foreground-prompt.md`.
  Tool returned RGB checkerboard instead of requested alpha. The app uses only
  its opaque table rectangle, cropped deterministically; no re-generation,
  AI cleanup, invented alpha or painted-over textures. Master retained for audit.

## Finishing and loop contract

Run from repository root:

```bash
bash Scripts/prepare-activity-scene.sh /path/to/4831-720.mp4 Assets/Activities/Park/table-source.png
```

- One 8-second 24 fps silent H.264 clip, 852 × 1108, approximately 1.3 MB.
- Background is frame zero. Only source y=180…530 is live, with 16-pixel feather
  edges, clear of the complete head-to-foot silhouette. Source crop x=360…914.
- At the beginning and end the visible path is empty. Opacity changes at 0…0.5 s
  and 7.3…7.8 s affect empty scenery only. No reverse walking, no actor crossfade,
  no interpolation-generated human frames. The last 0.2 seconds is the base frame.
- Decoded first/last-frame PSNR 45.63 dB after lossy encoding. This is an image
  difference check, not by itself proof of natural movement; contact sheets and
  application playback must also be inspected.
- Poster is extracted from the finished clip, so switching to static retains the
  crop and colour conversion. Table: source y=1058…1847. All layout is derived
  from the same 852 × 1847 canvas. No device-dependent safe-area background shift.

## Implementation and reuse

- `ActivitySceneView` uses existing `DSHologramSurface`, `DSHologramText`,
  `DSHologramSymbol` and `DSSceneActionCoordinator` without changing material
  colour, glow, shadows or 3D transforms. Scene-specific positions/angles are
  calibrated against the actual map, cup and journal.
- Profile's button style is extracted unchanged into `DSSceneEntranceButtonStyle`;
  profile and pilot now call the same implementation. 20 ms hold + 80 ms rebound
  + 20 ms wait remain unchanged.
- App composes destinations through the existing `SceneNavigationContainer`:
  opacity transition and leading-edge return are not a new feature-owned router.
- One `AVPlayer` + `AVPlayerLayer`; no per-frame SwiftUI
  timer, video-texture upload or full-page Metal rendering. Pause while covered,
  backgrounded, static, low-power or thermally constrained. Reduce Motion uses
  the poster. Release observers, player item and pending wake task when the pilot closes.
- Large accessibility text uses a readable alternate button layout.
- Loop is silent and never reconfigures the app's audio session.

## Acceptance

Inspect repeated loop boundaries for people popping, cutoff limbs, foliage seams,
background flashes and camera drift. Check static/dynamic crop parity, three
object anchors, actual category opening and left-edge return. Preserve the
original activity UI until the user approves this direction.

Initial pilot verified 2026-09-06 on the owned `LingoTrip-WT-c955` iPhone 17 Pro simulator:
`ActivitySceneTests` passed. It observes actual AVPlayer playback and two completed
AVPlayerLooper cycles before testing static/dynamic switching, opening the walking
category, leading-edge return, and closing the pilot. The shared navigation keeps
its root mounted, so the test checks hit-test visibility rather than AX existence.
Final app build passed. Phone energy/performance and user visual approval are still
pending; no phone installation is implied by these simulator checks.

## Object calibration and sparse ambience refinement

- No photographs or video pixels regenerated. `ActivitySceneGeometry.swift`
  records four-corner usable surfaces on the map, journal and cup. The cup is
  curved and the map folded: these are local visual fits, not inferred physical
  camera poses or a claim that either entire object is a perfect plane.
- Reuse Home's `HomeHomography` with a Core Animation projection of the existing
  SwiftUI hologram material. Each entrance has one centred 128 × 100 source layout,
  with a fixed 34:22 icon/text ratio. Its whole surface scales to the calibrated
  object footprint and the common photo-to-screen scale, not three unrelated
  font sizes. Text, symbol and shadow are projected together. Map gets the largest
  footprint, journal next, cup smallest; accessibility sizes retain plain controls.
- Scene-local footprint offset is (1.5, 3), extrusion (0.3, 0.7), before projection.
  Shared glow, colours and the profile/Home materials remain unchanged.
- Pixel comparison with an identically typeset plain label exposed a 12-point
  horizontal ink displacement from the shared text renderer's raster margin in
  this layout. `ActivitySceneLabel` compensates x only, before projection; y is
  unchanged. A 3× raster regression compares actual ink bounding-box centres,
  rather than assuming equal SwiftUI frames guarantee optical alignment.
- The 8-second file now plays as an event, **not an 8-second repeating schedule**.
  At its empty final frame the player pauses for a random 24–62 seconds, with a
  25% draw chance for a longer 65–95-second pause. A near-repeat delay is adjusted
  16 seconds away from the previous delay (overall bounds 24–95 seconds). Thus
  pass-to-pass intervals are at least 32 seconds, often longer. No reverse motion,
  speed randomization, human dissolve, or new synthetic person.
- Backgrounding, covering and switching to static cancel the wake task and retain
  remaining quiet time. Re-enabling does not immediately restart the same person.
  The next event seeks only between matching empty frames, waits for completion,
  then plays. Native APIs: https://developer.apple.com/documentation/avfoundation/avplayeritem
- UI test acceleration is opt-in via `UI_TEST_ACTIVITY_CADENCE=accelerated` in
  DEBUG only. A separate UI test uses actual production cooldown and checks that
  toggling does not cause a premature repeat. Policy tests cover 200 seeded draws.

### Further diversity, deliberately not faked in this revision

The remaining limitation is still one recognisable runner. Additional actors need
compatible licensed footage (camera height, travel direction, scale, light and
ground contact). Prefer multiple people from one locked-off take; composite only
after inspecting extraction edges and shadows. Future scheduling should use a
shuffle bag with per-actor cooldown, bounded occupancy and occasional long empty
periods, not independent uncontrolled random spawns. Ambient foliage/water can be
a separate subtle layer if matching footage exists; do not move the full camera
or pulse exposure just to hide repetition. These additions are not shipped here.

Refinement verification (2026-09-06, owned c955 simulator): all three
`ActivitySceneGeometryTests` passed, including 3× ink-centre comparison;
both `ActivitySceneTests` passed for sparse-event playback and navigation.
After the final x-only text correction, the production cooldown UI test was
rerun successfully and its full-screen attachment visually inspected. Existing
dependency-scan warnings remain; no source/media outside this pilot was changed.
