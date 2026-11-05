# Shared conversation implementation plan

Make concurrent signed-in devices share canonical message order, one durable reply producer, and recoverable reply state.

PostgreSQL owns one managed current conversation per account/character, canonical message indices, reply inputs, generation status and fencing. Message acceptance and generation scheduling commit together. API clients observe state and never independently generate or save managed assistant replies. Existing content synchronization remains the transport for persisted messages. Redis is disposable. Existing AI service owns provider admission and billing.

Server acceptance order governs cross-device messages. Client message IDs survive retries, and same-device batches preserve order. A generation snapshots its covered user messages before dispatch. Inputs accepted after dispatch wait for the next generation. Completion explicitly records coverage. No automatic second provider call after an uncertain dispatch. No long database transaction across network inference.

## 1. Isolate and establish baseline

- Work in codex/shared-chat-ordering at the managed worktree.
- Reuse installed dependency packages through ignored node_modules links.
- Run focused content-route and SSE tests. They must pass before changes.
- Start dedicated local PostgreSQL/Redis on 55435/56435 using build/chat-test-services and database lingotrip_test_shared_chat.

## 2. Specify shared conversation contracts with failing HTTP tests

- Create Backend/src/modules/chat/{contracts,routes,repository,service,prompt}.ts and Backend/test/integration/shared-chat.test.ts.
- POST /v1/chat/characters/:characterId/open opts the account into protocol 1 and returns canonical conversation ID and legacy aliases.
- GET /v1/chat/conversations/:conversationId returns accepted message records, revision, active generation and covered input IDs.
- POST /v1/chat/conversations/:conversationId/retry explicitly retries a failed generation with a command ID.
- Tests cover two authenticated device sessions, identical replay IDs, B-before-A arrival, atomic accept/schedule, new input during inference, complete-state replay, and stale producer fencing.

## 3. Persist canonical conversation and generation state

- Add additive migrations 0047_shared_chat.sql and 0048_shared_chat_indexes.sql, with journal entries.
- New tables record managed accounts, canonical sessions/aliases, message sequences, durable reply generations and generation input coverage.
- Extend the content commit observer to return an adjusted record. Run canonicalization before learning accounting and the existing sync writer.
- Adopt existing active conversation histories deterministically. Preserve archived sessions and existing message IDs. Publish migration changes through existing sync records.
- Canonicalize protected message fields on legacy content updates and prevent unmanaged assistant creation in managed sessions.
- Stable operation ID per generation drives existing credit idempotency. Legacy direct conversation requests for managed accounts require an update.

## 4. Implement durable reply processing

- Use the existing worker infrastructure to run asynchronous reply processing independently of other polling.
- Claim one eligible session/generation in a short transaction. Save immutable input snapshot, provider operation ID and fencing token before inference.
- Build model history from accepted server messages, character persona, learner difficulty, memory and explicit pending input coverage.
- Persist partial snapshots at a bounded cadence. Commit final assistant content and covered inputs transactionally and enqueue a next generation if needed.
- Recover a completed billed result by operation ID. An uncertain in-flight dispatch becomes a recoverable failure rather than an automatic new paid request.
- Unit/integration checks exercise failed/late/stale workers and ownership authorization.

## 5. Integrate native clients

- BackendKit gets typed shared-chat endpoints/models.
- CoreKit exposes a Sendable shared conversation gateway contract. SyncKit implements canonical activation, message upload, state observation and local record application.
- PersistenceKit preserves server order and canonical conversation identity. Pending local messages remain visible and stable by message ID.
- App assembly injects the gateway for authenticated workspaces. Tutorial/local preview remains an isolated fixture.
- ChatViewModel uses shared state for signed-in text, voice-message and real-time reply requests. The server saves generated assistant messages once.
- Poll/stream cancellation only stops observation. Device exit cannot cancel another device's producer. Retry references the existing message/generation.
- Focused hosted tests verify no local LLM generation in managed chats, repeated sends, canonical adoption and state recovery.

## 6. End-to-end verification and completion

- Run a real local HTTP server with two independently authenticated device sessions and a controlled local provider, dedicated database and Redis.
- Verify simultaneous sends, delayed delivery, duplicate transport retries, input during generation, disconnect/reconnect, producer restart and legacy-client rejection.
- Assert final message IDs/sequences/coverage, single published replies and provider invocation counts. Verify server-derived prompt sees preceding accepted context.
- Run affected backend checks and hosted Swift tests, build/install the latest iOS preview, inspect affected UI when available.
- Commit only explicit task paths after reviewing staged diffs. Deploy backend per repository owner authorization with data-preserving migrations and rollback readiness. Record exact verification results and remaining limitations.

## Verification record on 2026-11-05

- Backend unit suite passed 474 tests across 88 files, with 237 tests skipped by the normal suite configuration. Evidence is in `build/shared-chat-unit-suite-verified.log`.
- Focused PostgreSQL integration passed 18 tests. These cover ownership, canonical adoption, same-device predecessor deferral, lost acknowledgement replay, delayed timestamps, in-flight input, stale producers, explicit regeneration, metadata convergence, encounter archival and learning receipts. Evidence is in `build/shared-chat-integration-final.log`.
- Compiled API and worker process E2E passed 6 scenarios using two independently authenticated HTTP login sessions, dedicated PostgreSQL/Redis, a local streaming model fixture and the real credit ledger. The worker-death case holds the conversation commit until the model result is in the ledger, terminates only the test worker and verifies recovery without another provider call. Voice cases verify a live lease and continuation after a closed lease. Evidence is in `build/shared-chat-process-e2e-verified.log`.
- Hosted iOS tests passed 53 cases covering the shipping view model, SwiftData persistence and sync coordinator. Shared text and voice tests verify that the local LLM producer is unused and subtitle saving does not duplicate server replies. The snapshot regression verifies that direct state reads preserve the global sync cursor and server ordering. Evidence is in `build/shared-chat-swift-tests-verified.log`.
- Backend type checking, focused lint, dependency architecture and compilation passed. The full `pnpm check` stops at two existing non-null assertions in `test/unit/encounter-weights.test.ts`, lines 21 and 22. That file has no task changes.
- The preview script installed the current Debug app on simulator `659893A7-0822-43F4-8DA1-4A92E9C78814`. Computer Use opened Oliver's chat. A simulator screenshot confirms the header and composer layout. This is the isolated local preview. E2E model output comes from the controlled provider fixture.
- The isolated worktree's bundled dictionary was initially an LFS pointer. Hydrating that one existing resource allowed the hosted test runner to start. Its Git content remains unchanged.

## Operational handoff

The server accepts cross-device input in server sequence order and preserves client send time as message data. Inputs received after dispatch wait for another generation. An uncertain dispatch is checked against a saved ledger result. Explicit retry first restores that result when available, otherwise schedules one new generation and the client explains the potential additional charge.

All source changes are isolated on `codex/shared-chat-ordering`. The data-preserving rollback compatibility checkpoint is `bfbb6b13`, to be deployed before applying migrations 0047 and 0048. A deployment needs that preparatory release and the normal native-server migration and readiness steps.

Production deployment remains pending. The configured SSH attempt to `root@120.25.204.159` was rejected with public-key/password authentication failure. A request for the current host alias or configured key path is pending. Production acceptance requires the restored connection. The six local process E2E scenarios use a deterministic model fixture.
