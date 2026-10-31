import { readFile } from "node:fs/promises";
import { createHash } from "node:crypto";
import {
  activityWorldSchema,
  contentHash,
  requirePublishedWorld,
} from "../modules/npc/activity-world-content.js";

async function main() {
  const [mode, filename, legacyFilename] = process.argv.slice(2);
  if (
    !["validate", "release-check"].includes(mode ?? "") ||
    !filename ||
    !legacyFilename
  )
    throw new Error(
      "Usage: tsx src/cli/activity-world.ts validate|release-check WORLD.json ORIGINAL_LIBRARY.json",
    );
  const world =
    mode === "release-check"
      ? requirePublishedWorld(JSON.parse(await readFile(filename, "utf8")))
      : activityWorldSchema.parse(JSON.parse(await readFile(filename, "utf8")));
  const source = await readFile(legacyFilename);
  if (createHash("sha256").update(source).digest("hex") !== world.sourceSHA256)
    throw new Error("Original library bytes do not match the captured baseline");
  const legacy = JSON.parse(source.toString("utf8")) as {
    libraryVersion: string;
    entries: {
      id: string;
      travelerId: string;
      avatarId: string;
      avatarSHA256: string;
      card: unknown;
    }[];
  };
  if (
    legacy.libraryVersion !== world.sourceLibraryVersion ||
    legacy.entries.length !== world.characters.length
  )
    throw new Error("Original library version or identity count changed");
  for (const original of legacy.entries) {
    const person = world.characters.find((item) => item.id === original.id);
    if (
      !person ||
      person.travelerId !== original.travelerId ||
      person.avatarId !== original.avatarId ||
      person.avatarSHA256 !== original.avatarSHA256 ||
      person.sourceCardHash !== contentHash(original.card)
    )
      throw new Error(`Original identity or baseline mismatch: ${original.id}`);
  }
  process.stdout.write(
    JSON.stringify({
      releaseId: world.releaseId,
      status: world.status,
      cities: world.cities.length,
      places: world.places.length,
      characters: world.characters.length,
      assigned: world.characters.filter((person) => person.assignment).length,
      stories: world.stories.length,
      media: world.media.length,
      manifestHash: contentHash(world),
    }) + "\n",
  );
}

void main().catch((error: unknown) => {
  process.stderr.write(
    (error instanceof Error ? error.message : "Activity world validation failed") +
      "\n",
  );
  process.exitCode = 1;
});
