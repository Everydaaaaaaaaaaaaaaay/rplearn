# Ten-person NPC content pilot

Sample sources: `Content/NPCPilot/2026-09-11/`. These are review candidates, not a production roster import. Existing friends, avatars, databases and app routes are untouched by this pilot.

- `briefs.json`: ten independently authored narrative niches; accepted avatars supply only reviewed age/gender compatibility. Nationality, job and temperament are not inferred from images.
- `pilot-*.json`: curated character cards and complete seven-node binary stories (40 played paths).
- `profiles.json`: explicit narrative labels. Existing backend reconciliation plus 45 pair comparisons are in `diversity-audit.json`; this does not compare against live NPCs.
- `repairs.json`, `editorial-review.json`: semantic issues and editorial corrections. API format validity alone was insufficient. Short professional biographies tended toward similar careful/reflective personalities; assess lived interaction as well as categorical scores before scaling.
- `costs.json`: all 26 provider receipts, including failed format attempts and semantic rewrites. No unknown-cost attempts. USD × 7.2, not app credits or Codex usage.

Read-only checks and portable preview:

```sh
node Tools/ContentPipeline/verify-npc-pilot.mjs
python3 Tools/ContentPipeline/render-npc-pilot.py /tmp/npc-pilot-preview.html
```

The preview embeds the unchanged ten PNGs, works offline and offers clickable story branches. It does not add friends, call an LLM or implement iOS word lookup/audio. Existing iOS services can be connected in the later integration task.

## Explicitly authorized generation only

Run on a private server with Node 22+ and a protected provider env file. Never store the API key in source or generated content. The runner has **no database dependency** and logs request bodies/response receipts only to the private output directory, never authorization headers.

```sh
node --env-file=/secure/provider.env Tools/ContentPipeline/npc-pilot.mjs \
  Content/NPCPilot/2026-09-11/briefs.json /private/npc-pilot-output
# Optional, explicit semantic repair pass (at most two attempts per selected person):
node --env-file=/secure/provider.env Tools/ContentPipeline/npc-pilot.mjs \
  Content/NPCPilot/2026-09-11/briefs.json /private/npc-pilot-output \
  Content/NPCPilot/2026-09-11/repairs.json
```

GLM 5.3 Flash, minimal reasoning, Parasail preference with fallback, provider price ceilings of $0.20/M input and $0.60/M output, 14,000 output-token cap, concurrency 2. Shared ledger reserves a conservative maximum before dispatch and charges actual provider usage when returned. Unknown/interrupted attempts keep their upper estimate; they are never assumed free. Total pilot admission cap: CNY 3 at USD/CNY 7.2. Existing attempt IDs are not redispatched on resume.

The initial repair runner asked the model to repeat the whole character card, causing unnecessary retries when fields changed. The final runner preserves the original card in code and sends review instructions again on every repair attempt. First repair stories were recovered and manually edited for this delivered sample. Raw envelopes remain in the private experiment directory, not Git; generated review HTML is also outside Git.

Scaling to 200 still needs global deduplication, fuller semantic review, story coverage by scene/action, repeat-encounter handling, versioned import and client caching. One candidate per avatar must not overwrite previously bound public identities. No production deployment or device install is needed for this content-only pilot.

## Place-bound activity world authoring

The current source is `Content/ActivityWorld/2026-10-31-places-v1/`. Its fixed assignments determine identity, city, nationality and place before model requests. The writer receives the original card, exact photograph space facts and the other characters at that place. Named bilingual scene fields compile into the existing seven-node graph with four beats per node. The model does not allocate identities or invent graph edges.

```sh
node Tools/ContentPipeline/activity-world-author.mjs prepare \
  Content/ActivityWorld/2026-10-31-places-v1/world.json /private/activity-world-output
node --env-file=/private/openai.env Tools/ContentPipeline/activity-world-author.mjs stories \
  /private/activity-world-output/input.json /private/activity-world-output
node --env-file=/private/openai.env Tools/ContentPipeline/activity-world-author.mjs review \
  /private/activity-world-output/input.json /private/activity-world-output
node --env-file=/private/openai.env Tools/ContentPipeline/activity-world-author.mjs diversity \
  /private/activity-world-output/input.json /private/activity-world-output
node Tools/ContentPipeline/assemble-activity-world.mjs \
  Content/ActivityWorld/2026-10-31-places-v1/world.json \
  Content/ActivityWorld/2026-10-31-places-v1/assignments.json \
  /private/activity-world-output /private/activity-world-output/world-draft.json
```

Use `OPENAI_API_KEY` in a private environment file. Node 24's `--use-env-proxy` uses an existing proxy configuration when needed. Requests use OpenAI Responses with `store: false` and strict structured output. The author uses GPT-6.1 Sol and the independent model review uses GPT-5.4 mini. The runner defaults to a CNY 200 admission bound at USD/CNY 7.2. An explicit `authoringCapCNY` in the private input can change that operational bound, validated by the provider. The 2026-11-14 final repair pass used CNY 250. These are operator-chosen scheduling bounds, with actual estimated usage recorded separately. Native-provider token usage is reserved at the configured published price ceiling, with the cost basis explicitly labelled. This is an estimate for admission, not a provider invoice. Older pilot callers retain their own configured budgets and the CNY 35 default.

Keep request bodies, response envelopes, ledgers, environment files and generated previews outside Git. Reuse an existing output directory only for unchanged inputs, since receipt hashes reject changed requests. A `revisions.json` map can select a specific replacement result receipt for assembly. Keep the world a draft through generation and model review. Run the backend content validator against the assembled file and original library, then perform editorial continuity and cross-character review. Assembly has no database or activation dependency.

`review` examines all paths and the reunion for one person. `diversity` compares a whole city, including contact mechanisms, present states and reunion incidents. Curated repair input supplies `repairs` with exact `npcId` values and concrete instructions, plus a new `repairRound`. The `repair` phase replaces a complete candidate. The `patch` phase returns only changed nodes or reunion fields, uses null for unchanged fields, and compiles them into a complete receipt. Both phases store replacement receipts in `revisions.json`. Re-review selected revised people with `selectedIds` and a new `reviewRound`. These stages record evidence without granting automatic editorial approval.

The reviewer and assembler use the same `activity-world-editorial.mjs` projection for preserved biographies, curated migration notices and legacy-compatible reunion framing. Model flags require editorial adjudication. Original-card pronouns, a vocative addressed to another character, and quoted published letters must be read in context. Reunions can occur on another day with a new independent goal. Offline checks use `node --test Tools/ContentPipeline/library-provider.test.mjs Tools/ContentPipeline/activity-world-editorial.test.mjs`.
