# LingoTrip

Native SwiftUI iOS app + TypeScript/Fastify backend.

## Find the relevant code

Read only what the task needs. Swift dependencies: `Packages/LingoKit/Package.swift`;
Xcode targets/resources: `project.yml`; backend commands: `Backend/package.json`;
backend features: `Backend/src/modules/<module>/`. Use `docs/README.md` for domain
context and `docs/development.md` for verification examples; neither is a preflight checklist.
For assets, start with the nearest manifest or README.

## Essential boundaries

- App assembles navigation; Feature targets do not import other Feature targets.
- Declare Swift dependencies in `Package.swift`. Keep SwiftData entities inside
  PersistenceKit actors; expose `Sendable` DTOs across actors and to UI.
- Backend routes call services; repositories own transactions. Cross-module access
  uses types/services, with assembly in `server.ts`, `worker.ts` or infrastructure.
- PostgreSQL is authoritative; Redis is disposable. Provider secrets stay server-side.
- Preserve user data and historical migrations. Never delete a database to fix a failure.

## Verify and finish

Choose checks for the changed behavior and risk; stop when evidence is sufficient.
Docs-only changes need diff/link/command checks, not an app build. Use Xcode-hosted
Swift tests (`Scripts/test.sh -only-testing:...`, or the focused scripts in the development
guide); do not run `swift build` inside `Packages/LingoKit`. Local unit tests need no
repeated approval. Database tests require an isolated environment; live AI evaluations,
production probes and deployments require the corresponding task authorization.

Standing owner authorization (2026-09-11): after completing backend changes and
relevant checks, deploy them to production and verify the affected online behavior
without asking again, unless the user explicitly defers deployment. Preserve data
and rollback readiness. Backend deployment does not publish an iOS App Store build.

For photographic scenes, use `docs/activity-scene-visual-acceptance.md` and the latest
scene record. Reuse unchanged evidence; verify affected visuals and each open user issue.
Keep a per-version record; rejected or unverified assets are not release-ready.

Inspect Git status first and preserve unrelated work. Finish with a focused commit unless
asked otherwise: stage explicit task paths, inspect the staged diff, and report verification
and remaining unrelated changes. Exclude generated output, caches, credentials and local
configuration. Do not rewrite commits or destructively reset worktrees without explicit permission.

Standing owner instruction (2026-09-11): automatically create a focused commit after
each completed and verified logical change, without waiting for a separate commit request.
Continue to stage only task-related paths and preserve unrelated work.
