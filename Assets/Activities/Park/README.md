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

- One 81-second, 24 fps silent H.264 loop at 852 × 1108. It contains one natural-
  speed runner pass near the beginning and 74 seconds of moving empty scenery.
- The empty scenery is a three-second forward-only loop made from the person-free
  source interval 1.1…4.1 seconds and a 1.1-second environmental dissolve back
  through source 0…1.1. It repeats 27 times, so trees, grass and distant bridge
  traffic keep moving for the whole 81 seconds instead of freezing with the runner.
- The runner event uses source 1.1…8.25 at unchanged timing. It fades in during
  the empty opening and fades back only after the runner has left the crop, so the
  person is always fully opaque while visible. Both sides of the outer loop use
  the ambient layer. There is no reverse playback, slow motion, duplicated actor,
  frozen waiting interval or interpolation-generated human frame.
- The 3-second environmental seam, the event-to-environment return and the 81-second
  outer seam require normal-speed application review. Codec/file facts and still
  frames do not by themselves prove that distant vehicles or foliage blend naturally.
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
- One `AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`; no per-frame SwiftUI
  timer, video-texture upload or full-page Metal rendering. Pause while covered,
  backgrounded, static, low-power or thermally constrained. Reduce Motion uses
  the poster. Release observers and queued player items when the pilot closes.
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
- The old event-player cooldown was rejected because pausing its single player also
  froze the bridge and foliage. The final 81-second asset now owns both cadence and
  continuous ambience; the app player never enters a synthetic quiet/frozen state.
- The same runner appears once per 81-second loop. Pausing for navigation, app
  backgrounding, static mode, power or thermal policy pauses the complete scene as
  expected; ordinary empty time does not. There is no DEBUG cadence override.
- The cup and table belong to the first-person user. The cup entrance is titled
  “喝口咖啡” and starts from a shared view of the bridge; it never describes a
  passer-by taking the user's seat or sharing the user's table.

### Further diversity, deliberately not faked in this revision

The remaining limitation is still one recognisable runner. Additional actors need
compatible licensed footage (camera height, travel direction, scale, light and
ground contact). Prefer multiple people from one locked-off take; composite only
after inspecting extraction edges and shadows. Do not add them by copying the one
runner or by freezing the environment between events. These additions are not
shipped here.

The earlier sparse-event verification remains historical evidence for entrance
geometry only; it does not validate the replacement 81-second media or continuous
playback. Current results and open visual checks are recorded in
`Assets/Activities/RealMotion-v5/acceptance-v5.md`.
