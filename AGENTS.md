# LingoTrip

Native SwiftUI iOS app + TypeScript/Fastify backend. Read the files relevant to the
requested change; no mandatory repo scan or document preflight.

## Where to look

- Swift dependencies: `Packages/LingoKit/Package.swift`; Xcode targets/resources: `project.yml`.
- Backend commands/tools: `Backend/package.json`; feature code: `Backend/src/modules/<module>/`.
- Architecture: `docs/architecture.md`; domain docs: `docs/README.md`. Read them when needed.
- Task routing and verification examples: `docs/development.md`. `Scripts/code-map.sh <scope>`
  is an optional lookup, not a prerequisite to editing.
- For assets/models, start from the nearest manifest or README. Generated projects, build
  output, caches and binary assets are not architecture sources; inspect them only when relevant.

## Boundaries

- App assembles navigation. Feature targets do not import other Feature targets.
- Declare Swift dependencies in `Package.swift`. Keep SwiftData entities inside PersistenceKit
  actors; cross-actor/UI values are `Sendable` DTOs.
- Backend routes call services; repositories own transactional persistence. Modules expose
  types/services, not another module's repository/schema. Cross-module assembly belongs in
  `server.ts`, `worker.ts` or an infrastructure capability.
- PostgreSQL is authoritative; Redis is disposable. Provider secrets stay server-side.
- Preserve user data on migration failure. Never delete a database to make a test/build pass.

## Completion and verification

Carry the requested change through relevant verification and fix failures it causes. Choose
checks by changed behavior and risk: a focused test, build or visual inspection is often enough.
Docs-only edits need no app build. Do not automatically chain targeted tests, full suites,
repeated passes and Release builds. Broaden when shared contracts, failures or release scope
justify it; stop when the relevant evidence is sufficient.

Local unit tests use mocks/in-memory fixtures and can be run and repaired without repeated
approval. Database suites need an explicitly isolated test environment. Live AI evaluations,
production probes and deployments are separate workflows; ordinary tests do not authorize them.
Use Xcode-hosted tests (`Scripts/test.sh` with `-only-testing:...`); do not run `swift build`
inside `Packages/LingoKit`. Historical calibration/production logs are evidence, not standing gates.

## Git

Inspect status before editing; preserve unrelated pre-existing changes. Finish completed work
with a focused commit unless the user says otherwise. Stage explicit task paths, inspect the
staged diff, and report verification and any remaining unrelated changes. Exclude generated
build output, caches, credentials and local configuration. Do not rewrite existing commits
without an explicit request. When synchronizing worktrees, preserve their work and use merges
or fast-forwards rather than destructive resets.
