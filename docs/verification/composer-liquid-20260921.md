# Composer liquid — 2026-09-21

## Scope

Replaces the blurred full-width waterline in the existing chat composer. Translation flow, field layout and compact composer height are unchanged.

- Local Metal renderer, no new dependencies or resources. Water surface and submerged body are separate analytic layers, with far/near edges, bounded roll/pitch, broad reflection, a subtly displaced internal light field, and a meniscus.
- Final rounded signed-distance mask confines every layer and decoration to a 6 pt inset. The existing illuminated top rim remains above the render layer.
- Blue: a 10 pt lemon slice and two small bubbles. Purple: a small petal and bubbles. Decorations rotate/drift with the same damped state; lower portions fade as if submerged. No emoji assets or hit targets.
- 30 Hz live device-motion input with a noise deadband; spring simulation subdivides at 120 Hz maximum timestep. Display targets 60 Hz during motion, 30 Hz in low-power/serious thermal state. CADisplayLink is invalidated when settled, hidden/backgrounded, or Reduce Motion is enabled. Actual achieved FPS is not asserted.
- Mode switching uses one renderer and preserves motion state; a radial reveal originates at the mascot. Text and buttons remain outside the shader.
- Reduce Transparency uses an opaque, flat tinted backing; Reduce Motion uses a static surface. Unsupported Metal falls back to the normal backing.

## Evidence

- Initial unit run: 7 passed, 0 failed, `build/DerivedData/VerificationResults/20260921T114859Z-66944.xcresult`.
- Initial UI run: 1 passed, 0 failed, `build/DerivedData/VerificationResults/20260921T115013Z-67945.xcresult`. Verified Chinese/English draft preservation, toggles, AI button and hidden input disabled state.
- Initial screenshot inspection found overly bright surface highlights; reduced them before final acceptance.
- Computer Use enumerated Device Hub, but opening it timed out. Used focused XCTest screenshot capture instead.

## Physical-device limitation

Device inventory reports the iPhone 13 as paired but not connected. Connection was requested. Physical tilt response, perceived material quality on the phone, sustained GPU frame time and energy impact remain pending real-device verification. Simulator rendering and deterministic GPU/physics tests do not establish those results.

## Final checks

- Final physics/shader/GPU + translation unit run: **8 passed, 0 failed**, `build/DerivedData/VerificationResults/20260921T115234Z-68583.xcresult`.
- GPU test renders three pitch values at extreme roll, checks alpha is zero outside the inner walls, checks the center is rendered, and confirms pitch changes the output.
- Dark-mode UI regression: **1 passed, 0 failed**, `build/DerivedData/VerificationResults/20260921T115327Z-69452.xcresult`. Screenshot inspected: Chinese and English remain legible, water and small decorations remain behind controls, surface highlights are restrained.
- Added explicit view-visibility gating so leaving chat stops both sampling and display updates, even when navigation retains the view.
- `Scripts/check-architecture.sh --ios` and `git diff --check`: passed.
- Final light-mode UI regression after visibility gating: **1 passed, 0 failed**, `build/DerivedData/VerificationResults/20260921T115503Z-69960.xcresult`. Both normal and expanded captures retained in the result bundle.
