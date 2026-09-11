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
