import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { integrationConfig } from "../helpers/integration.js";
import { activityWorldFixture } from "../helpers/activity-world.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { createDomainActivityContext } from "../../src/modules/domain/service.js";
import { createOutingService } from "../../src/modules/npc/outing-service.js";
import { importActivityWorld } from "../../src/modules/npc/outing-repository.js";
import { contentHash } from "../../src/modules/npc/activity-world-content.js";
import type {
  OutingService,
  OutingSnapshot,
} from "../../src/modules/npc/outing-types.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "place-bound outings in an isolated database",
  () => {
    let runtime: RuntimeDependencies, service: OutingService;
    const world = activityWorldFixture();
    const viewer = randomUUID(),
      guest = randomUUID(),
      other = randomUUID();
    const firstPlace = world.places.find((place) => place.cityId === "london");
    if (!firstPlace) throw new Error("Missing place fixture");
    const placeId = firstPlace.id;
    const start = (runId: string = randomUUID(), selectedPlace: string = placeId) => ({
      runId,
      releaseId: world.releaseId,
      placeId: selectedPlace,
    });
    let roll = 0;
    const apply = async (
      snapshot: OutingSnapshot,
      type: "presented" | "complete" | "abandon",
    ) =>
      service.apply(viewer, snapshot.runId, {
        type,
        operationId: randomUUID(),
        expectedRevision: snapshot.revision,
      });
    async function show(snapshot: OutingSnapshot) {
      let current = snapshot;
      const beats =
        current.mode === "reunion"
          ? current.story?.reunion.beats
          : current.story?.nodes.find((node) => node.id === "start")?.beats;
      for (let index = 0; index < (beats?.length ?? 0); index += 1)
        current = await service.apply(viewer, current.runId, {
          type: "read",
          beatIndex: index,
          operationId: randomUUID(),
          expectedRevision: current.revision,
        });
      return apply(current, "presented");
    }
    beforeAll(async () => {
      runtime = createRuntimeDependencies(integrationConfig(process.env));
      await runMigrations(runtime.database);
      await runtime.start();
      await runtime.database.sql.begin(async (sql) => {
        for (const user of [viewer, guest, other]) {
          await sql`insert into app.users(id) values(${user})`;
          await sql`insert into app.user_profiles(user_id,current_region_id,starter_region_id,has_completed_onboarding)
          values(${user},'london','london',true)`;
        }
        await sql`insert into app.guest_installations(user_id,installation_hash) values(${guest},${guest.replaceAll("-", "").repeat(2)})`;
        for (const person of world.characters) {
          await sql`insert into app.npc_avatars(id,image_url,tags)
          values(${person.avatarId},${`https://example.com/${person.avatarId}.jpg`},'[]')`;
          await sql`insert into app.public_npcs(id,traveler_id,avatar_id,card,card_hash)
          values(${person.id},${person.travelerId},${person.avatarId},${JSON.stringify(person.originalCard)}::jsonb,${contentHash(person.originalCard)})`;
        }
      });
      await importActivityWorld(runtime.database, world, true);
      service = createOutingService(
        runtime.database,
        createDomainActivityContext(runtime.database),
        () => roll,
      );
    });
    afterAll(async () => {
      // A dedicated database owns these fixture identities; no production fallback is allowed.
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition -- beforeAll may fail before assigning runtime.
      if (!runtime) return;
      await runtime.database
        .sql`delete from app.users where id=any(${[viewer, guest, other]}::uuid[])`;
      await runtime.database
        .sql`delete from app.npc_activity_worlds where release_id=${world.releaseId}`;
      await runtime.database
        .sql`delete from app.public_npcs where id=any(${world.characters.map((person) => person.id)}::uuid[])`;
      await runtime.database
        .sql`delete from app.npc_avatars where id=any(${world.characters.map((person) => person.avatarId)}::uuid[])`;
      await runtime.close();
    });

    it("imports without overwriting original cards and rejects changing an existing release", async () => {
      const person = world.characters[0];
      if (!person) throw new Error("Missing person");
      const [row] = await runtime.database.sql<
        { card: unknown }[]
      >`select card from app.public_npcs where id=${person.id}`;
      expect(row?.card).toEqual(person.originalCard);
      const changed = structuredClone(world);
      changed.cities[0] = {
        ...changed.cities[0],
        id: "london",
        nameZh: "修改",
        populationTarget: 18,
      };
      await expect(
        importActivityWorld(runtime.database, changed, true),
      ).rejects.toThrow("immutable");
    });

    it("lists only local places and rejects cross-city start, including guest requests", async () => {
      const catalog = await service.catalog(viewer);
      expect(catalog?.places).toHaveLength(5);
      expect(
        catalog?.places.every(
          (place) =>
            world.places.find((item) => item.id === place.id)?.cityId === "london",
        ),
      ).toBe(true);
      const foreign = world.places.find((place) => place.cityId === "newyork");
      if (!foreign) throw new Error("Missing foreign place");
      await expect(
        service.start(viewer, start(randomUUID(), foreign.id)),
      ).rejects.toMatchObject({ code: "OUTING_WRONG_CITY" });
      await expect(
        service.start(guest, start(randomUUID(), foreign.id)),
      ).rejects.toMatchObject({ code: "OUTING_WRONG_CITY" });
    });

    it("reserves once across devices, does not mark unseen NPCs met, and keeps exact-place eligibility", async () => {
      const input = start();
      const [first, retry] = await Promise.all([
        service.start(viewer, input),
        service.start(viewer, input),
      ]);
      expect(retry).toEqual(first);
      expect(first.mode).toBe("first_meeting");
      const person = world.characters.find((entry) => entry.id === first.npc?.id);
      expect(person?.assignment?.placeId).toBe(placeId);
      const [history] = await runtime.database.sql<
        { count: number }[]
      >`select count(*)::int as count from app.npc_encounter_history where user_id=${viewer}`;
      expect(history?.count).toBe(0);
      await expect(service.start(viewer, start())).rejects.toMatchObject({
        code: "OUTING_ALREADY_ACTIVE",
      });

      await expect(
        service.start(viewer, { ...input, placeId: world.places[1]?.id ?? "missing" }),
      ).rejects.toMatchObject({ code: "OUTING_CONFLICT" });
      expect(await service.active(viewer)).toEqual(first);
      await expect(service.find(other, first.runId)).rejects.toMatchObject({
        code: "OUTING_NOT_FOUND",
      });
      await apply(first, "abandon");
    });

    it("serializes a new outing with a concurrent city change", async () => {
      const held = Promise.withResolvers<boolean>();
      const resume = Promise.withResolvers<boolean>();
      const travel = runtime.database.sql.begin(async (sql) => {
        await createDomainActivityContext(runtime.database).lock(sql, viewer);
        held.resolve(true);
        await resume.promise;
        await sql`update app.user_profiles set current_region_id='newyork' where user_id=${viewer}`;
      });
      await held.promise;
      const reservation = service.start(viewer, start());
      resume.resolve(true);
      await travel;
      await expect(reservation).rejects.toMatchObject({ code: "OUTING_WRONG_CITY" });
      await runtime.database
        .sql`update app.user_profiles set current_region_id='london' where user_id=${viewer}`;
    });

    it("confirms presentation exactly once and restores snapshots after travel or release deactivation", async () => {
      let current = await service.start(viewer, start());
      current = await show(current);
      const npcId = current.npc?.id;
      const operation = {
        type: "read" as const,
        beatIndex: current.beatIndex,
        operationId: randomUUID(),
        expectedRevision: current.revision,
      };
      const saved = await service.apply(viewer, current.runId, operation);
      expect(await service.apply(viewer, current.runId, operation)).toEqual(saved);
      await expect(
        service.apply(viewer, current.runId, { ...operation, beatIndex: 0 }),
      ).rejects.toMatchObject({ code: "OUTING_CONFLICT" });
      const [history] = await runtime.database.sql<
        { encounters: number }[]
      >`select encounters from app.npc_encounter_history where user_id=${viewer} and npc_id=${npcId ?? null}`;
      expect(history?.encounters).toBe(1);
      await runtime.database
        .sql`update app.user_profiles set current_region_id='newyork' where user_id=${viewer}`;
      await runtime.database
        .sql`update app.npc_activity_worlds set enabled=false where release_id=${world.releaseId}`;
      expect(await service.find(viewer, current.runId)).toEqual(saved);
      expect(await service.start(viewer, start(current.runId))).toEqual(saved);
      await apply(saved, "abandon");
      await runtime.database
        .sql`update app.user_profiles set current_region_id='london' where user_id=${viewer}`;
      await runtime.database
        .sql`update app.npc_activity_worlds set enabled=true where release_id=${world.releaseId}`;
    });

    it("counts shown solitude only, guarantees an encounter, and preserves removed contacts", async () => {
      await runtime.database
        .sql`delete from app.npc_outing_city_progress where user_id=${viewer}`;
      roll = 0.99;
      for (let index = 0; index < 2; index += 1) {
        let current = await service.start(viewer, start());
        expect(current.mode).toBe("solitude");
        current = await apply(current, "presented");
        await apply(current, "complete");
      }
      let guaranteed = await service.start(viewer, start());
      expect(guaranteed.npc).not.toBeNull();
      guaranteed = await show(guaranteed);
      await apply(guaranteed, "abandon");
      const ids = world.characters
        .filter((person) => person.assignment?.placeId === placeId)
        .map((person) => person.id);
      for (const id of ids)
        await runtime.database
          .sql`insert into app.user_npc_relationships(user_id,npc_id,local_character_id,status)
        values(${viewer},${id},${id},'removed') on conflict(user_id,npc_id) do update set status='removed'`;
      roll = 0;
      let empty = await service.start(viewer, start());
      expect(empty.reason).toBe("empty_pool");
      expect(empty.npc).toBeNull();
      empty = await apply(empty, "presented");
      await apply(empty, "complete");
      const [remaining] = await runtime.database.sql<
        { count: number }[]
      >`select count(*)::int as count
      from app.user_npc_relationships where user_id=${viewer} and npc_id=any(${ids}::uuid[]) and status='removed'`;
      expect(remaining?.count).toBe(ids.length);
    });
  },
);
