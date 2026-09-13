# Dictionary examples: cached or on-device — 2026-09-13

The app resolver sends `generateOnMiss: false` for every dictionary example lookup.
Ready translations retain the existing sentence and contextual meaning. Missing and
pending entries return immediately, without enqueueing generation or polling. The
card's existing Apple Translation coordinator handles uncached sentences; a failed
cache request also falls through to Apple. Local-only output does not invent a
context-specific dictionary meaning.

Passive translation uses installed language packs; explicit retry can request a
supported language pack download. Unsupported/unavailable local translation stays
retryable and never switches to cloud generation. Tutorial fixtures are unchanged.

No server deployment is needed: the existing resolve endpoint already returns before
generation when `generateOnMiss` is false. Old app versions and already queued jobs
can still generate translations; this change does not erase cached data or history.

Verification: Xcode-hosted BackendDictionaryExampleTranslationsTests (ready/missing/
pending all make exactly one cache-only request) and DictExampleFallbackTests (cache
hit, miss, language-pack policy). Apple model execution requires physical hardware;
the simulator checks the routing contract, not translation quality.

Result: all 4 tests in 2 suites passed, including 3 parameterized cache states.
Result bundle: `/tmp/example-cache-only-retry.xcresult`.
