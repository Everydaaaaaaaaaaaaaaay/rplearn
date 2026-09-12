# Welcome screenshots · v1 (retired)

Superseded by the user-requested concept previews on 2026-09-12. These eight screenshots
are no longer bundled. The capture scripts and hashes remain as historical provenance.

Four product views, each in light and dark appearance. Captured on a **physical iPhone 13**
using `xcrun devicectl device capture screenshot` on 2026-09-12. No generated mock UI.
The asset catalogue contains rectangular crops encoded as JPEG; original pixel hashes and
crop coordinates are in `captures-v1.json`. Total bundled JPEG data: 2,231,831 bytes.

- Activity: actual `ActivitiesView`, park actions. Existing scene artwork is unchanged;
  this screenshot shows the physical device's static/reduced-motion rendering. It is not
  new approval of the activity motion loop (see `../Activities/RealMotion-v5/acceptance-v5.md`).
- Chat: actual `ChatView` with bundled Ruby portrait and six locally seeded example messages.
- Dictionary: actual point-word overlay for `cosy`; dictionary entries are unchanged.
  Two example translations are supplied as fixture data through the normal translation action.
- Companion: actual `CharacterSelectView` using Oliver's bundled card and portrait.

## Capture safely

Install the Debug app, unlock the paired iPhone, then run:

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  python3 Assets/Welcome/capture-on-device.py DEVICE_UDID /tmp/welcome-capture
python3 Assets/Welcome/import-screenshots.py /tmp/welcome-capture
```

The explicit DEBUG-only `UI_TEST_WELCOME_CAPTURE` flag bypasses session restoration **without
logging out or clearing credentials**. Screens use an in-memory workspace. Do not use
`UI_TEST_FORCE_SIGNED_OUT` on an owner's phone: that older test flag calls logout.
The capture script relaunches normally in `finally`, restoring the usual account UI.
No messages are sent and no live AI services are used during capture.

`WelcomeCaptureTests` exercises the same screens on an isolated simulator. Physical XCTest
runner bootstrapping failed (exit 74); these final assets came from devicectl screenshots,
not from the failed test runs or simulator captures. Final layout verification is recorded
in `../../docs/welcome-onboarding-2026-09-12.md`.
