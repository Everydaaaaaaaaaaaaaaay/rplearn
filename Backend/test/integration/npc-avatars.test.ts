import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { loadConfig } from "../../src/config/env.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createNpcService, type NpcService } from "../../src/modules/npc/service.js";
import { avatarMetadata, npcCard } from "../helpers/npc-avatars.js";

// Use a disposable PostgreSQL database: these tests never depend on Redis or external AI.
describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "per-user permanent avatar bindings",
  () => {
    let db: DatabaseResource;
    let service: NpcService;
    const users = [randomUUID(), randomUUID()] as const;
    const avatar = randomUUID();
    const variant = randomUUID();
    const family = randomUUID();
    const npc = randomUUID();
    const others = [randomUUID(), randomUUID()] as const;
    beforeAll(async () => {
      db = createDatabase(
        loadConfig({
          NODE_ENV: "test",
          DATABASE_URL:
            process.env.DATABASE_URL ?? "postgres://127.0.0.1:5432/lingotrip",
        }),
      );
      await runMigrations(db);
      service = createNpcService(db);
      for (const user of users)
        await db.sql`insert into app.users (id) values (${user})`;
      for (const id of [avatar, variant])
        await db.sql`
      insert into app.npc_avatars (id, family_id, image_url, metadata)
      values (${id}, ${family}, ${`https://example.com/${id}.png`}, ${JSON.stringify(avatarMetadata)}::jsonb)
    `;
    });
    afterAll(async () => {
      for (const user of users) await db.sql`delete from app.users where id = ${user}`;
      for (const id of [npc, ...others])
        await db.sql`delete from app.public_npcs where id = ${id}`;
      for (const id of [avatar, variant])
        await db.sql`delete from app.npc_avatars where id = ${id}`;
      await db.close();
    });
    it("makes concurrent same-NPC retries idempotent and preserves removed status", async () => {
      const user = users[0];
      const results = await Promise.all(
        Array.from({ length: 8 }, () =>
          service.register(user, { id: npc, card: npcCard }),
        ),
      );
      expect(new Set(results.map((value) => value.avatar?.id)).size).toBe(1);
      await service.link(user, npc, { localCharacterId: npc, status: "removed" });
      const replay = await service.register(user, { id: npc, card: npcCard });
      expect(replay.avatar).toEqual(results[0]?.avatar);
      const [row] =
        await db.sql`select status from app.user_npc_relationships where user_id = ${user} and npc_id = ${npc}`;
      expect(row?.status).toBe("removed");
      // Even physically deleting the relationship does not release an encounter's avatar.
      await db.sql`delete from app.user_npc_relationships where user_id = ${user} and npc_id = ${npc}`;
      await expect(
        service.register(user, { id: others[0], card: npcCard }),
      ).rejects.toMatchObject({ code: "NPC_AVATAR_UNAVAILABLE" });
      expect((await service.find(user, replay.travelerId)).avatar).toEqual(
        replay.avatar,
      );
    });
    it("permits reuse across users but never across NPCs or variants within one user", async () => {
      const user = users[1];
      const results = await Promise.allSettled(
        others.map((id) => service.register(user, { id, card: npcCard })),
      );
      expect(results.filter((value) => value.status === "fulfilled")).toHaveLength(1);
      expect(results.filter((value) => value.status === "rejected")).toHaveLength(1);
      const [count] =
        await db.sql`select count(*)::int as count from app.user_npc_avatars where family_id = ${family}`;
      expect(count?.count).toBe(2);
    });
    it("keeps identity immutable and suppresses withdrawn images without reallocating", async () => {
      await expect(
        service.register(users[0], {
          id: npc,
          card: { ...npcCard, name: "Different" },
        }),
      ).rejects.toMatchObject({ code: "NPC_IDENTITY_CONFLICT" });
      await db.sql`update app.npc_avatars set withdrawn = true where family_id = ${family}`;
      const result = await service.register(users[0], { id: npc, card: npcCard });
      expect(result.avatar).toBeNull();
      const [count] =
        await db.sql`select count(*)::int as count from app.user_npc_avatars where user_id = ${users[0]}`;
      expect(count?.count).toBe(1);
    });
  },
);
