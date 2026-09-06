import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { integrationConfig as loadConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { createNpcService, type NpcService } from "../../src/modules/npc/service.js";
import { newEntityId } from "../../src/shared/id.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "scene selection and friend limits",
  () => {
    let runtime: RuntimeDependencies;
    let service: NpcService;
    const viewer = newEntityId();
    const limitViewer = newEntityId();
    const firstNPC = newEntityId();
    const npcs = [firstNPC, ...Array.from({ length: 5 }, () => newEntityId())];
    const avatars = npcs.map(() => newEntityId());
    const duplicate = newEntityId();
    const context = {
      regionId: "london",
      activityId: `museum-${viewer}`,
      category: "culture" as const,
      language: "English",
    };

    beforeAll(async () => {
      const config = loadConfig({ ...process.env, NODE_ENV: "test" });
      runtime = createRuntimeDependencies(config);
      await runMigrations(runtime.database);
      await runtime.start();
      service = createNpcService(runtime.database, () => 0);
      for (const id of [viewer, limitViewer]) {
        await runtime.database.sql`insert into app.users (id) values (${id})`;
        await runtime.database
          .sql`insert into app.guest_installations (user_id, installation_hash) values (${id}, ${id.replaceAll("-", "").repeat(2)})`;
      }
      await runtime.database
        .sql`insert into app.user_profiles(user_id,starter_region_id,current_region_id,has_completed_onboarding)
        values (${viewer},'london','london',true),(${limitViewer},'london','london',true)`;
      for (const [i, id] of npcs.entries()) {
        const avatar = avatars[i];
        if (!avatar) throw new Error("Missing fixture avatar");
        await runtime.database
          .sql`insert into app.npc_avatars (id, image_url, tags) values (${avatar}, ${`https://example.com/${avatar}.png`}, '[]')`;
        const card = {
          age: 29,
          gender: "female",
          name: `Museum guide ${String(i)}`,
          occupation: "guide",
          regionId: i === 2 ? "newyork" : "london",
          hobbies: ["art"],
          nationality: "British",
          personality: "curious",
          appearance: "short hair",
          languages: i === 3 ? ["French"] : ["English"],
          personaVoice: {
            anchorLines: [],
            boundaries: [],
            conversationalHabits: [],
            flaws: [],
            values: [],
          },
        };
        await runtime.database
          .sql`insert into app.public_npcs (id, traveler_id, avatar_id, card, card_hash)
        values (${id}, ${String(90000000000 + i + Number.parseInt(viewer.slice(-5), 16) * 10)}, ${avatar}, ${JSON.stringify(card)}::jsonb, ${"a".repeat(64)})`;
        await runtime.database
          .sql`insert into app.npc_scene_affinities (npc_id, region_id, activity_id, category, language)
        values (${id}, 'london', ${i >= 4 ? "different-activity" : context.activityId}, 'culture', 'English')`;
      }
      await runtime.database
        .sql`insert into app.public_npcs (id, traveler_id, avatar_id, card, card_hash)
      select ${duplicate}, ${String(80000000000 + Number.parseInt(viewer.slice(-5), 16))}, avatar_id, card, card_hash from app.public_npcs where id = ${firstNPC}`;
    });

    afterAll(async () => {
      for (const id of [viewer, limitViewer])
        await runtime.database.sql`delete from app.users where id = ${id}`;
      for (const id of [...npcs, duplicate])
        await runtime.database.sql`delete from app.public_npcs where id = ${id}`;
      for (const id of avatars)
        await runtime.database.sql`delete from app.npc_avatars where id = ${id}`;
      await runtime.database
        .sql`delete from app.npc_scene_supply where activity_id = ${context.activityId}`;
      await runtime.close();
    });

    it("requires scene and language compatibility, preserves friendship, and avoids repeats and occupied portraits", async () => {
      await service.link(viewer, firstNPC, {
        localCharacterId: firstNPC,
        status: "friend",
      });
      const selected = await service.selectEncounter(viewer, context);
      expect(selected.candidateCount).toBe(2);
      expect(selected.npc?.id).toBe(npcs[0]);
      const [relation] = await runtime.database
        .sql`select status from app.user_npc_relationships where user_id = ${viewer} and npc_id = ${firstNPC}`;
      expect(relation?.status).toBe("friend");
      expect((await service.selectEncounter(viewer, context)).npc?.id).toBe(npcs[1]);
      expect((await service.selectEncounter(viewer, context)).reason).toBe(
        "coverage_gap",
      );
      await service.link(viewer, firstNPC, {
        localCharacterId: firstNPC,
        status: "removed",
      });
      await expect(
        service.link(viewer, duplicate, {
          localCharacterId: duplicate,
          status: "candidate",
        }),
      ).rejects.toMatchObject({ code: "NPC_AVATAR_ALREADY_SEEN" });
    });

    it("serializes concurrent additions at three guest slots and keeps existing friends on retries", async () => {
      const results = await Promise.allSettled(
        npcs
          .slice(0, 4)
          .map((id) =>
            service.link(limitViewer, id, { localCharacterId: id, status: "friend" }),
          ),
      );
      expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(3);
      expect(results.filter((r) => r.status === "rejected")).toHaveLength(1);
      const rows = await runtime.database.sql<
        { npc_id: string }[]
      >`select npc_id::text from app.user_npc_relationships where user_id = ${limitViewer} and status = 'friend'`;
      expect(rows).toHaveLength(3);
      const id = rows[0]?.npc_id;
      if (typeof id !== "string") throw new Error("Missing friend fixture");
      await service.link(limitViewer, id, { localCharacterId: id, status: "friend" });
    });
  },
);
