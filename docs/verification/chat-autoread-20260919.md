# Chat automatic reading — 2026-09-19

Scope: first-enable NPC omissions and speech ending before the full bubble has played.

## Changes

- ChatView applies playback eligibility and message changes as one snapshot. On an enable transition, only the previous snapshot is history; an incoming NPC bubble in the same update remains eligible. Reapplying an enabled configuration no longer consumes unseen messages.
- Finishing a page load restores the actual playback eligibility instead of unconditionally disabling the queue. Empty observations do not permanently consume a message ID.
- Apple TTS registers its waiter before submitting the utterance. It no longer infers completion from the instantaneous `isSpeaking` flag. Each utterance has its own completion UUID, so a delayed finish/cancel from a replaced synthesizer cannot release the next utterance's waiter. Explicit stop still releases the current waiter.
- NPC delivery was inspected: complete bubble text is appended after reply formatting; streaming preview text is separate. Supertonic concatenates every synthesis segment before PCM playback, and PCM completion already waits for producer completion plus buffer drain. No comma-based truncation was found in those paths.

These are confirmed lifecycle defects/races in the code. The exact failing utterance and device trace from the report were not available, so a device-specific synthesis failure has not been independently reproduced or ruled out.

## Verification

Command (Xcode-hosted):

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer Scripts/test.sh \
  -only-testing:LingoTripTests/ChatAutoReadQueueTests \
  -only-testing:LingoTripTests/SpeechServiceTests \
  '-only-testing:LingoTripTests/SpeechDeliveryTests/segmentation()' \
  -only-testing:LingoTripTests/NarrativeAudioPlayerTests
```

40 passed, 0 failed, 0 skipped. Result: `build/DerivedData/VerificationResults/20260919T111944Z-62903.xcresult` (generated, not committed).

Coverage includes user/NPC FIFO, first-enable concurrent arrival, repeated configuration, empty-then-complete message, full comma-containing text, history/deduplication, rapid off/on, completion ownership, cancellation, speech routing, PCM buffering policy and narrative playback regression.

An earlier broader run passed 33 tests and failed `SpeechDeliveryTests.preparedCollection()`: the unchanged London `nora_intro` text does not match its prerecorded voice entry. This separate asset issue is not concealed by the focused run; no story text or voice assets were changed here.

The initial build also encountered stale generated SpeechKit modules; the existing test script removed the outdated module mirror on the next run. No user data was cleared.

UI regression: `Scripts/test-ui.sh -only-testing:LingoTripUITests/ChatKeyboardTests/testAutomaticReadingToggle` passed (1 test). Result: `build/DerivedData/VerificationResults/20260919T112015Z-63372.xcresult`. The retained screenshot was inspected: enabled speaker icon, full header and message layout are intact. Computer Use did not expose the simulator app, so the existing native UI test supplied the interaction and screenshot evidence.

`Scripts/preview.sh preview messages` installed and launched the latest tested app on the existing iPhone 17 Pro simulator. This is a local preview, not a physical-device audio verification or TestFlight release.
