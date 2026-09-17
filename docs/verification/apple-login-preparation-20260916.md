# Apple login preparation recovery — 2026-09-16

## Root cause and scope

The former sign-in view made one POST to `/v1/auth/apple/challenge` on appearance and mapped every failure to “Apple 登录暂不可用”. Transport intentionally fails fast on unavailable connectivity; the view had no network recovery subscription. The reported individual network failure cannot be reconstructed from the screenshot. The current production challenge endpoint returned 200 during diagnosis.

## Changes

- A dedicated main-actor preparation owner deduplicates concurrent refreshes, tries transient failures up to three times with 1/2-second delays, and stops automatic retry for permanent configuration failures.
- NWPathMonitor and CTCellularData observe network restoration and first-launch cellular permission grants. Foreground reentry retries unavailable preparation.
- Challenges renew 30 seconds before expiration, conservatively counting TTL from request start. The nonce is pinned while Apple authorization and server login exchange are in progress. Cancellation/failure prepares a new nonce; the actual login exchange is never automatically replayed.
- View disappearance cancels monitoring/work; generation checks reject late responses. Disabled state applies to accessibility as well as touch. Connection, service and configuration failures have distinct messages; manual retry remains available.
- Local diagnostics record attempt number and failure category only, never nonce, credentials or identity tokens. No backend routes or authentication validation changed.

## Verification

- 15 hosted Swift tests passed, zero failures/skips: `build/DerivedData/VerificationResults/20260916T012518Z-92617.xcresult` (7 preparation recovery tests plus 8 existing BackendClient authentication tests).
- Initial test compilation encountered stale BackendKit module visibility; normal incremental `Scripts/preview.sh build me` resolved it. Final incremental build/install passed after the accessibility and message wrapping adjustment.
- Local HTTP fixture returned 503, 503, then 200 for exactly three challenge requests. Simulator restored the normal black Apple button automatically. Fixture stopped afterward. No Apple authorization or login submission was performed.
- Simulator screenshots inspected: `build/apple-login-20260916/recovered.png` and `offline.png`; preparation recovery and offline error text render correctly without clipping.
- Computer Use Device Hub connection failed with -10005 / AppleEvent timeout. No interactive Apple-sheet or physical-device permission-dialog verification claimed.
- Latest build installed through `Scripts/preview.sh`; simulator left at the login screen using the normal production backend. Friends need an updated TestFlight build; none uploaded by this task.
