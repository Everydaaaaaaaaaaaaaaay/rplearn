# Sequential chat bubble reading — 2026-09-16

- Added a default-off, per-chat speaker toggle inside the existing trailing system glass toolbar group, before call/settings. Enabled icon is filled blue; disabled icon is gray/slashed; accessibility reports 开启/关闭.
- New user and assistant text messages are observed in persisted message order. Existing messages are seeded as seen; translation, metadata refresh and repeated snapshots never replay a bubble. Does not replay recorded voice messages or speak quiz payloads.
- FIFO uses the real SpeechService `speakAndWait` completion, with existing local engines and character voice hints. User text uses pronunciation voice. No AI requests or billing changes.
- Closing/disappearing, backgrounding, recording, calls, details and lookup sheets stop/clear the automatic queue. Resuming starts from new messages. Manual bubble playback explicitly stops the automatic queue first.
- Stop operations form a barrier before newly enabled playback; cancellation/generation guards prevent an old worker from consuming or stopping a new queue.

## Evidence

- Three hosted queue tests passed: `build/DerivedData/VerificationResults/20260916T015802Z-95586.xcresult`. Controlled speech completions verify mixed user/NPC FIFO, no interruption by new arrivals, snapshot deduplication/history skipping, queue clearing and rapid toggle stop ordering.
- Focused toolbar UI test passed: `build/DerivedData/VerificationResults/20260916T020200Z-97258.xcresult`. Default-off → on → off accessibility values checked. Earlier attempt missed navigation into Ruby chat; corrected test taps the visible message row.
- Reviewed enabled screenshot `build/chat-autoread-review/41ABDFD9-9C5E-49A2-814D-0F016954AE0A.png`: three controls share one capsule, title remains readable, speaker is highlighted.
- Device Hub Computer Use remains unavailable (-10005 earlier this session); focused Xcode automation used. Physical-device listening not verified in this task.
- Incremental build succeeded. Latest app installed with `Scripts/preview.sh`; simulator left in isolated Ruby chat preview. No account data or backend changes.
