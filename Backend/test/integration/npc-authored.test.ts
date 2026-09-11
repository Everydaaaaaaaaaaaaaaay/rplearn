import { readFileSync } from "node:fs";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { integrationConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { createNpcService } from "../../src/modules/npc/service.js";
import { importAuthoredLibrary } from "../../src/modules/npc/authored-library-repository.js";
import { authoredLibrarySchema } from "../../src/modules/npc/authored-content.js";
import { newEntityId } from "../../src/shared/id.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "production authored roster",
  () => {
    let runtime: RuntimeDependencies;
    const viewer = newEntityId(),
      guest = newEntityId(),
      oldID = newEntityId();
    const manifest = () =>
      authoredLibrarySchema.parse(
        JSON.parse(
          readFileSync(
            new URL("../../../App/Resources/npc-library-v3.json", import.meta.url),
            "utf8",
          ),
        ),
      );
    beforeAll(async () => {
      runtime = createRuntimeDependencies(
        integrationConfig({ ...process.env, NODE_ENV: "test" }),
      );
      await runMigrations(runtime.database);
      await runtime.start();
      for (const id of [viewer, guest])
        await runtime.database.sql`insert into app.users(id) values(${id})`;
      await runtime.database
        .sql`insert into app.guest_installations(user_id,installation_hash) values(${guest},${guest.replaceAll("-", "").repeat(2)})`;
      await runtime.database
        .sql`insert into app.user_profiles(user_id,starter_region_id,current_region_id,has_completed_onboarding) values(${guest},'london','london',true)`;
      for (const entry of manifest().entries) {
        const profile = {
          sha256: entry.avatarSHA256,
          gender: entry.card.gender,
          ageMin: entry.card.age,
          ageMax: entry.card.age,
          appearance: entry.card.appearance,
          styleVersion: "test",
        };
        await runtime.database
          .sql`insert into app.npc_avatars(id,image_url,tags,profile) values(${entry.avatarId},${`https://example.com/${entry.avatarId}.webp`},'[]',${JSON.stringify(profile)}::jsonb)`;
      }
      const first = manifest().entries[0];
      if (!first) throw Error("Missing first character");
      await runtime.database
        .sql`insert into app.public_npcs(id,traveler_id,avatar_id,card,card_hash) values(${oldID},'99999999999',${first.avatarId},${JSON.stringify(first.card)}::jsonb,${"0".repeat(64)})`;
      await runtime.database
        .sql`insert into app.user_npc_relationships(user_id,npc_id,local_character_id,status) values(${viewer},${oldID},${oldID},'friend')`;
    });
    afterAll(async () => {
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
      if (!runtime) return;
      for (const id of [viewer, guest])
        await runtime.database.sql`delete from app.users where id=${id}`;
      await runtime.database
        .sql`delete from app.public_npcs where id=any(${[oldID, ...manifest().entries.map((e) => e.id)]}::uuid[])`;
      await runtime.database
        .sql`delete from app.npc_avatars where id=any(${manifest().entries.map((e) => e.avatarId)}::uuid[])`;
      await runtime.database
        .sql`delete from app.npc_library_versions where version=${manifest().libraryVersion}`;
      await runtime.close();
    });
    it("imports atomically, releases old binding without deleting friendship, and rejects version changes", async () => {
      const value = manifest();
      expect(await importAuthoredLibrary(runtime.database, value)).toBe(200);
      expect(await importAuthoredLibrary(runtime.database, value)).toBe(200);
      const [old] = await runtime.database
        .sql`select n.avatar_id,r.status from app.public_npcs n join app.user_npc_relationships r on r.npc_id=n.id where n.id=${oldID}`;
      expect(old).toMatchObject({ avatar_id: null, status: "friend" });
      const changed = structuredClone(value);
      const changedEntry = changed.entries[0];
      if (!changedEntry) throw Error("Missing character");
      changedEntry.summaryZh += "修改";
      await expect(importAuthoredLibrary(runtime.database, changed)).rejects.toThrow(
        "immutable",
      );
      const broken = structuredClone(value);
      broken.libraryVersion += "-broken";
      const brokenEntry = broken.entries[199];
      if (!brokenEntry) throw Error("Missing character");
      brokenEntry.avatarSHA256 = "0".repeat(64);
      await expect(importAuthoredLibrary(runtime.database, broken)).rejects.toThrow(
        "Avatar compatibility",
      );
      const [version] = await runtime.database
        .sql`select count(*)::int as count from app.npc_library_versions where version=${broken.libraryVersion}`;
      expect(version?.count).toBe(0);
      const [pool] = await runtime.database
        .sql`select count(*)::int as count from app.npc_scene_affinities where library_version=${value.libraryVersion}`;
      expect(pool?.count).toBe(200);
      const source = value.entries[0];
      if (!source) throw Error("Missing character");
      await expect(
        createNpcService(runtime.database, () => 0).register(guest, {
          id: newEntityId(),
          card: {
            ...source.card,
            name: "Legacy registration fixture",
            occupation: "satellite telemetry archivist",
            hobbies: ["underwater hockey", "collecting meteorite catalogues"],
            personality:
              "An independent fixture who collects orbital telemetry and prefers long, solitary dives.",
            background:
              "Maintains a private archive of satellite downlinks and studies underwater navigation.",
            speechStyle: "Slow factual remarks about orbital telemetry.",
            personaVoice: {
              values: ["precise orbital timestamps", "independent navigation"],
              flaws: ["forgets terrestrial appointments", "overpacks diving charts"],
              boundaries: ["no archive lending", "no team competitions"],
              conversationalHabits: [
                "compares orbital periods",
                "describes diving routes",
              ],
              anchorLines: ["That downlink belongs to another orbit."],
            },
          },
        }),
      ).rejects.toMatchObject({ code: "NPC_AVATAR_COVERAGE_GAP" });
    });
    it("reaches every actual character, replays runs once, and respects guest cities", async () => {
      const value = manifest();
      const reached = new Set<string>();
      const groups = new Map(
        value.entries.map((e) => [
          e.card.regionId + "/" + e.story.actionId,
          {
            regionId: e.card.regionId,
            activityId: e.story.actionId,
            category: "social" as const,
            language: "English",
          },
        ]),
      );
      // One or two cards per city/action: extreme draws prove both remain selectable.
      for (const context of groups.values())
        for (const fraction of [0, 0.999999999]) {
          const service = createNpcService(runtime.database, (max) =>
            Math.floor(max * fraction),
          );
          const run = { libraryVersion: value.libraryVersion, runId: newEntityId() };
          const selected = await service.selectEncounter(viewer, context, run);
          expect(selected.npc).not.toBeNull();
          if (!selected.npc) throw Error("Unreachable character pool");
          reached.add(selected.npc.id);
          expect(await service.selectEncounter(viewer, context, run)).toEqual(selected);
          const [count] = await runtime.database
            .sql`select count(*)::int as count from app.npc_authored_encounter_runs where user_id=${viewer} and run_id=${run.runId}`;
          expect(count?.count).toBe(1);
          await expect(
            service.selectEncounter(viewer, { ...context, language: "French" }, run),
          ).rejects.toMatchObject({ code: "NPC_ENCOUNTER_CONFLICT" });
        }
      expect(reached.size).toBe(200);
      const [history] = await runtime.database
        .sql`select sum(encounters)::int as count from app.npc_encounter_history where user_id=${viewer}`;
      expect(history?.count).toBe(270);
      const service = createNpcService(runtime.database, () => 0);
      await expect(
        service.selectEncounter(
          guest,
          {
            regionId: "melbourne",
            activityId: "park-route",
            category: "social",
            language: "English",
          },
          { libraryVersion: value.libraryVersion, runId: newEntityId() },
        ),
      ).rejects.toMatchObject({ code: "LOGIN_REQUIRED" });
      await expect(
        service.selectEncounter(
          viewer,
          {
            regionId: "london",
            activityId: "park-route",
            category: "social",
            language: "English",
          },
          { libraryVersion: "missing", runId: newEntityId() },
        ),
      ).rejects.toMatchObject({ code: "NPC_LIBRARY_UNAVAILABLE" });
    });
  },
);
