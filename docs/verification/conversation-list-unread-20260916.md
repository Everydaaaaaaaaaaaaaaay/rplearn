# Conversation list unread refresh — 2026-09-16

The root tab observed `roleplayConversationDidChange`, but ConversationListView did not. A reply delivered after navigating back could update the tab count while leaving row summaries and avatar badges stale until a later reload.

The visible list now observes that same event. Refreshes replace the projected row summaries, updating badges, latest text and ordering together. Hidden lists defer to their normal appearance reload to avoid disturbing chat navigation. A generation guard rejects outdated overlapping reload results.

Verification:
- 24 ChatWorkflowTests passed, including `visibleListRefreshesForBackgroundReply`: mounts the production ConversationListView in a hosted window with in-memory real SwiftData stores, lets its initial load settle, delivers a reply through ChatViewModel while the list stays mounted, and checks the row-derived persisted total catches up without navigation.
- 3 ConversationReadStateTests passed.
- Results: `build/DerivedData/VerificationResults/20260916T023807Z-3617.xcresult` and `20260916T023658Z-2680.xcresult`. The first attempt at filtering an individual Swift Testing test only ran the read-state suite; the complete workflow suite was then run and the new test's Passed result explicitly verified.
- Latest compiled app installed using `Scripts/preview.sh preview messages`. No network AI calls, backend changes or real account writes. Physical-phone navigation not verified in this task.
