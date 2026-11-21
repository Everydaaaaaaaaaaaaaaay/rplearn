import { readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { integrationConfig } from "../helpers/integration.js";
import {
  requirePublishedWorld,
  contentHash,
} from "../../src/modules/npc/activity-world-content.js";
import { createDomainActivityContext } from "../../src/modules/domain/service.js";
import { createOutingService } from "../../src/modules/npc/outing-service.js";
import { importActivityWorld } from "../../src/modules/npc/outing-repository.js";
import { NpcRepository } from "../../src/modules/npc/repository.js";
import { advanceOuting, outingBeats } from "../../src/modules/npc/outing-state.js";
import type { OutingSnapshot } from "../../src/modules/npc/outing-types.js";

const world = requirePublishedWorld(
  JSON.parse(
    readFileSync(
      new URL("../../config/activity-world/2026-10-31-places-v1.json", import.meta.url),
      "utf8",
    ),
  ),
);

function play(source: OutingSnapshot, first: number, second: number) {
  let current = source;
  const apply = (
    operation:
      | { type: "read"; beatIndex: number }
      | { type: "choice"; choiceId: string }
      | { type: "presented" | "complete" },
  ) => {
    current = advanceOuting(current, {
      ...operation,
      expectedRevision: current.revision,
      operationId: randomUUID(),
    });
  };
  for (let stage = 0; stage < 3; stage += 1) {
    for (let beatIndex = 0; beatIndex < outingBeats(current).length; beatIndex += 1)
      apply({ type: "read", beatIndex });
    if (stage === 0) apply({ type: "presented" });
    if (stage < 2)
      apply({
        type: "choice",
        choiceId: `${current.nodeId}:${String(stage === 0 ? first : second)}`,
      });
    else apply({ type: "complete" });
  }
  return current;
}

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "complete published activity world",
  () => {
    let database: DatabaseResource;
    const viewers = new Map(world.cities.map((city) => [city.id, randomUUID()]));
    beforeAll(async () => {
      database = createDatabase(integrationConfig());
      await runMigrations(database);
      await database.sql.begin(async (sql) => {
        for (const [city, user] of viewers) {
          await sql`insert into app.users(id) values(${user})`;
          await sql`insert into app.user_profiles(user_id,current_region_id,starter_region_id,has_completed_onboarding)
          values(${user},${city},${city},true)`;
        }
        for (const person of world.characters) {
          await sql`insert into app.npc_avatars(id,image_url,tags) values(${person.avatarId},${`https://example.com/${person.avatarId}.jpg`},'[]')`;
          await sql`insert into app.public_npcs(id,traveler_id,avatar_id,card,card_hash)
          values(${person.id},${person.travelerId},${person.avatarId},${JSON.stringify(person.originalCard)}::jsonb,${contentHash(person.originalCard)})`;
        }
      });
    });
    afterAll(async () => {
      // This runner owns an isolated database and these exact fixture identities.
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
      if (!database) return;
      await database.sql`delete from app.users where id=any(${[...viewers.values()]}::uuid[])`;
      await database.sql`delete from app.npc_activity_worlds where release_id=${world.releaseId}`;
      await database.sql`delete from app.public_npcs where id=any(${world.characters.map((person) => person.id)}::uuid[])`;
      await database.sql`delete from app.npc_avatars where id=any(${world.characters.map((person) => person.avatarId)}::uuid[])`;
      await database.close();
    });

    it("admits all cities, reserves each of the 200 exact-place identities, plays 800 paths and selects reunions", async () => {
      await importActivityWorld(database, world, true);
      expect(await importActivityWorld(database, world, true)).toMatchObject({
        manifestHash: contentHash(world),
        enabled: true,
      });
      const service = createOutingService(
        database,
        createDomainActivityContext(database),
        () => 0,
      );
      const seen = new Set<string>();
      let paths = 0;
      for (const [city, user] of viewers) {
        const catalog = await service.catalog(user, world.releaseId);
        expect(catalog?.cityId).toBe(city);
        expect(catalog?.places.length).toBeGreaterThanOrEqual(3);
        for (const place of catalog?.places ?? []) {
          expect(place.photo.placeId).toBe(place.id);
          const people = world.characters.filter(
            (person) => person.assignment?.placeId === place.id,
          );
          for (const person of people) {
            expect(person.assignment?.cityId).toBe(city);
            const publicPerson = await new NpcRepository(database).find(
              person.travelerId,
            );
            expect(publicPerson.card).toEqual(person.assignment?.card);
            expect(publicPerson.id).toBe(person.id);
            let current = await service.start(user, {
              runId: randomUUID(),
              releaseId: world.releaseId,
              placeId: place.id,
            });
            expect(current.mode).toBe("first_meeting");
            expect(current.npc?.card.regionId).toBe(city);
            expect(people.some((person) => person.id === current.npc?.id)).toBe(true);
            if (!current.npc) throw new Error("Missing published person");
            expect(seen.has(current.npc.id)).toBe(false);
            seen.add(current.npc.id);
            for (const first of [0, 1])
              for (const second of [0, 1]) {
                expect(play(current, first, second).status).toBe("completed");
                paths += 1;
              }
            for (
              let beatIndex = 0;
              beatIndex < outingBeats(current).length;
              beatIndex += 1
            )
              current = await service.apply(user, current.runId, {
                type: "read",
                beatIndex,
                operationId: randomUUID(),
                expectedRevision: current.revision,
              });
            current = await service.apply(user, current.runId, {
              type: "presented",
              operationId: randomUUID(),
              expectedRevision: current.revision,
            });
            await service.apply(user, current.runId, {
              type: "abandon",
              operationId: randomUUID(),
              expectedRevision: current.revision,
            });
          }
          const reunion = await service.start(user, {
            runId: randomUUID(),
            releaseId: world.releaseId,
            placeId: place.id,
          });
          expect(reunion.mode).toBe("reunion");
          expect(reunion.story?.reunion.beats.length).toBeGreaterThanOrEqual(4);
          await service.apply(user, reunion.runId, {
            type: "abandon",
            operationId: randomUUID(),
            expectedRevision: reunion.revision,
          });
        }
      }
      expect(seen.size).toBe(200);
      expect(paths).toBe(800);
    }, 60_000);
  },
);
