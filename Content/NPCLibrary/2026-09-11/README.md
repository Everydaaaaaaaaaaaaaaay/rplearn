# Preauthored 200-person library

The release resource is `App/Resources/npc-library-v3.json`, library version **2026-09-12-v3**. It contains 200 avatar-bound characters, 200 seven-node first meetings (800 complete paths) and 200 independent reunions. The approved ten-person pilot is the editorial reference. See [release acceptance](release-acceptance.md) for exact resource hash, checks and editorial limits.

`briefs.draft.json` is rejected historical planning. `briefs.production.json` fixes identities and compatibility; the final resource incorporates the explicit directions and exact-content revisions in this directory. `editorial-final-yvonne.json` replaces the duplicated object-naming mechanism; `editorial-final-casey.json` differentiates invitation plots. Other editorial files repair branch continuity, person-level dynamics, reader perspective and reunion collisions. Sources containing `expectedContent` preserve before/after evidence; only the assembled app resource is runtime content.

## Identity and reachability

All 200 accepted v3 avatars are used exactly once. Age range, creative gender and appearance come from verified `observed` metadata and image hashes; occupation, nationality, personality and history were authored independently. The ten pilot identities remain, with factual story repairs where necessary. The pilot action `park-map` is normalized to the actual app action `park-route`.

The roster covers all 15 cities × 9 current social actions, with 1–2 people per city/action. A 40% uniform exploration component mixed with soft scene/recency weights gives each eligible NPC at least 20% conditional probability in these slots. This bound is conditional on choosing their city/action and the outing yielding a person. It does not promise a meeting after a fixed number of outings. City access and removed-contact exclusions remain effective.

The importer atomically replaces avatar allocation and the scene pool, preserving existing people, friendships and messages. Ruby is preserved. Repeated encounter runs replay the same choice; an existing contact receives a reunion rather than an unchosen first-meeting branch as invented history.

## Playback

The 15-second outing animation precedes locally authored playback. Choices advance the local graph, followed by Add Friend / Leave. Lookup and NPC voice playback remain available. Encounter text and character creation require no live generation request. Later ordinary NPC chat is separate and can still consume credits.

## Editorial evidence and budget

Every final card and story has an exact-content review hash. Global screening combines cohort audits, a complete roster of reviewed person/plot summaries and complete reunions, and exact incremental checks after edits. All prior candidates are retained for full-record adjudication. Explicit editorial decisions explain false positives using the complete records. Changed content invalidates those decisions; the builder checks global snapshots, individual reviews and both pair hashes.

`npc-similarity.mjs` compares all 19,900 pairs per category with English token Jaccard and exact eight-word passages. This is candidate screening, not proof of absolute semantic uniqueness. Shared settings, ordinary politeness, common hobbies and broad traits are allowed; duplicated underlying characters, incidents or branch consequences require differentiation. Rejected model planning and incomplete responses are not release approvals.

All planning, generation and reviews share a durable **CNY 35** cap, increased from CNY 25 with user authorization on 2026-09-12. Final receipted spend is CNY 30.8353; accounting including seven unknown-cost upper bounds is CNY 34.7089. Unknown attempts are never silently retried or treated as free. These are GLM provider costs, not Codex usage or app-user credits. Provider receipts and credentials stay outside the repository and app.

Rebuild requires the private evidence directory:

```sh
node Tools/ContentPipeline/build-npc-library.mjs PRIVATE_OUTPUT App/Resources/npc-library-v3.json 2026-09-12-v3
node Tools/ContentPipeline/verify-npc-library.mjs
node --test Tools/ContentPipeline/library-provider.test.mjs
```
