import { readFile } from "node:fs/promises";
import type { DatabaseResource } from "../../db/client.js";
import { importActivityWorld } from "./outing-repository.js";

const baseReleaseId = "2026-10-31-places-v1";
export const bundledActivityWorld = new URL(
  "../../../config/activity-world/2026-11-22-encounters-v2.json",
  import.meta.url,
);

export async function publishBundledActivityWorld(database: DatabaseResource) {
  // A fresh database needs the original NPC identities and world seeded first.
  const [base] = await database.sql`
    select 1 from app.npc_activity_worlds where release_id=${baseReleaseId} and enabled
  `;
  if (!base) return null;

  const world: unknown = JSON.parse(await readFile(bundledActivityWorld, "utf8"));
  return importActivityWorld(database, world, true);
}
