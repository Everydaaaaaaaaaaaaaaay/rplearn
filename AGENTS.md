# LingoTrip agent map

LingoTrip is a monorepo containing a native SwiftUI iOS app and a TypeScript/Fastify backend. Start with the smallest task-specific surface below; do not scan the whole repository.

## Sources of truth

- Swift target graph: `Packages/LingoKit/Package.swift`
- Xcode targets, schemes, resources, and generated project settings: `project.yml`
- Backend commands and pinned tools: `Backend/package.json`
- Backend database assembly: `Backend/src/db/schema.ts` and `Backend/src/db/user-schema.ts`; feature tables stay in each `Backend/src/modules/*/schema.ts`
- Stable system boundaries and data flows: `docs/architecture.md`
- Product-specific behavior: read the matching file linked from `docs/README.md` only when the task needs it

The generated `LingoTrip.xcodeproj/`, `build/`, package build products, lock artifacts, binary models, SQLite dictionaries, and image assets are not architecture sources.

## Task routing

| Change | Read first | Then, only if needed |
| --- | --- | --- |
| App startup or dependency construction | `App/LingoTripApp.swift`, `App/AppEnvironment.swift` | `App/RootView.swift` |
| Tabs, navigation, or feature composition | `App/RootView.swift`, `App/AppNavigationState.swift` | the destination `*Feature` |
| Chat UI or state | `ChatFeature/ChatView.swift`, `ChatFeature/ChatViewModel.swift` | `DomainKit/Conversation`, `LLMKit`, `PersistenceKit/Stores/ChatStore.swift` |
| Prompting, memory, quiz, relationship logic | the named file in `DomainKit/Conversation` | its matching `DomainKitTests` file |
| Travel, economy, progression, or story rules | the matching folder in `DomainKit` | `PersistenceKit` store and backend `domain` module |
| Local data or sync | `PersistenceKit/Schema`, the named `PersistenceKit/Stores` file | `SyncKit`, backend `content`/`sync` |
| Speech or realtime voice | `SpeechKit` or `RealtimeVoiceKit` | `docs/realtime-voice.md` for lifecycle constraints |
| Swift module dependency | `Packages/LingoKit/Package.swift` | `project.yml` only when the App/test target also changes |
| Backend HTTP endpoint | `Backend/src/modules/<module>/routes.ts` | `service.ts`, then the smallest repository file involved |
| Backend process composition | `Backend/src/server.ts` or `Backend/src/worker.ts` | `Backend/src/infrastructure` |
| Backend configuration | `Backend/src/config/env.ts`; read `env-types.ts` only when changing the config contract | `.env.example` and config tests |
| Database change | owning module `schema.ts`; shared user identity starts in `Backend/src/db/user-schema.ts` | repository, migration, integration test |
| City/story content | `App/Resources/regions.json` or the named story JSON | `DomainKit/Story`, `docs/journey-design.md` |
| Images, mascot, or bundled models | the nearest manifest/report/README | binary files only when the task explicitly requires them |

Run `Scripts/code-map.sh` for the compact repository map. Pass a Swift target such as `ChatFeature` or a backend scope such as `backend:auth` to list only that module's files and public/exported symbols.

## Boundaries that matter

- `App/` is the iOS composition root. Feature targets do not import other Feature targets; navigation between features is assembled in App.
- Swift target dependencies are declared only in `Package.swift`. Prefer source-file splits inside the owning target over creating a new target without a distinct dependency boundary.
- SwiftData entities stay inside PersistenceKit actors. Cross-actor and UI APIs use `Sendable` DTOs.
- Backend modules expose contracts through `types.ts` and service factories. Routes call services; repositories own transactional persistence.
- Backend modules must not import another module's repository or schema internals. Cross-module orchestration belongs in `server.ts`, `worker.ts`, or an infrastructure capability.
- PostgreSQL is authoritative business state. Redis state must be disposable. AI provider secrets never belong in the client.

## Local verification

Choose the narrowest relevant command, then widen for cross-module changes:

```bash
Scripts/check-architecture.sh
Scripts/test-conversation.sh
Scripts/test-relationship.sh
Scripts/test.sh
Scripts/build.sh

cd Backend
pnpm test
pnpm check
pnpm build
```

Do not run `swift build` directly inside `Packages/LingoKit`; package tests are compiled through the Xcode-hosted test targets defined in `project.yml`.

## Task-scoped clean commits

- Finish every completed user task with one focused commit unless the user explicitly asks not to commit. A task may use more than one commit only when independently reviewable stages materially improve safety or clarity.
- Before editing, inspect `git status`. Treat all pre-existing changes as user-owned unless their origin is known; do not fold unrelated work into the task commit, discard it, or rewrite it to obtain a clean tree.
- Keep the commit limited to the current task. Stage explicit paths only—never use broad staging such as `git add .` or `git add -A`—and inspect the staged diff before committing.
- Run the narrowest relevant verification before the commit. Do not commit generated build products, caches, credentials, local configuration, screenshots, or temporary analysis artifacts.
- Use a concise commit message that states the outcome. Do not amend, squash, rebase, force-push, or rewrite existing commits unless the user explicitly requests it.
- After committing, confirm that no changes from the completed task remain unstaged or untracked. A worktree containing unrelated pre-existing changes is acceptable, but report them clearly rather than claiming the entire tree is clean.

## Default reading exclusions

Unless the task is specifically about these artifacts, do not inspect:

- `build/`, `DerivedData/`, `Packages/LingoKit/.build/`, `Backend/node_modules/`, `Backend/dist/`, coverage output
- `App/Assets.xcassets/`, `Assets/**/raw/`, rendered analysis directories
- `*.bin`, `*.safetensors`, `*.mlmodelc`, `*.sqlite`, `*.glb`, `*.blend`, audio, video, and raster image contents

Use manifests, licenses, reports, filenames, and targeted metadata reads before opening any heavy resource.
