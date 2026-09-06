import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { loadConfig } from "../../src/config/env.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import {
  createAccessService,
  type AccessService,
} from "../../src/modules/access/service.js";
import { newEntityId } from "../../src/shared/id.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "persistent access ledger",
  () => {
    let runtime: RuntimeDependencies;
    let access: AccessService;
    const guest = newEntityId(),
      free = newEntityId();
    beforeAll(async () => {
      runtime = createRuntimeDependencies(
        loadConfig({ ...process.env, NODE_ENV: "test" }),
      );
      await runMigrations(runtime.database);
      await runtime.start();
      access = createAccessService(runtime.database);
      await runtime.database.sql`insert into app.users(id) values (${guest}),(${free})`;
      await runtime.database
        .sql`insert into app.guest_installations(user_id, installation_hash) values (${guest},${guest.replaceAll("-", "").repeat(2)})`;
    });
    afterAll(async () => {
      await runtime.database.sql`delete from app.users where id in (${guest},${free})`;
      await runtime.close();
    });
    it("serializes lifetime reservations, refunds failure and replays without consuming again", async () => {
      const original = await access.snapshot(guest);
      expect(original.policy.isGuest).toBe(true);
      expect(original.resetsAt).toBeNull();
      const ids = Array.from({ length: original.balances.chat.limit + 5 }, () =>
        newEntityId(),
      );
      const results = await Promise.allSettled(
        ids.map((id) => access.reserve(guest, id, id, "chat")),
      );
      const accepted = ids.filter((_, index) => results[index]?.status === "fulfilled");
      expect(accepted).toHaveLength(original.balances.chat.limit);
      const id = accepted[0];
      if (id === undefined) throw new Error("No reservation accepted");
      await expect(access.reserve(guest, id, id, "chat")).rejects.toMatchObject({
        code: "OPERATION_IN_PROGRESS",
      });
      await access.settle(guest, id, false);
      await access.reserve(guest, id, id, "chat");
      await access.settle(guest, id, true, { content: "hello" });
      expect((await access.reserve(guest, id, id, "chat")).result).toEqual({
        content: "hello",
      });
      await expect(access.reserve(guest, id, "changed", "chat")).rejects.toMatchObject({
        code: "OPERATION_CONFLICT",
      });
      await runtime.database
        .sql`update app.usage_operations set created_at=now()-interval '2 days' where user_id=${guest} and status='succeeded'`;
      expect(
        (await createAccessService(runtime.database).snapshot(guest)).balances.chat
          .remaining,
      ).toBe(0);
      await access.stopVoice(guest, id);
      expect((await access.snapshot(guest)).balances.chat.used).toBe(1);
    });
    it("free daily windows replenish while timed-out voice is charged and cannot replay free time", async () => {
      const initial = await access.snapshot(free);
      expect(initial.policy.friendSlotLimit).toBe(5);
      expect(initial.resetsAt).not.toBeNull();
      const operation = newEntityId();
      await access.reserve(free, operation, "daily", "advanced");
      await access.settle(free, operation, true);
      await runtime.database
        .sql`update app.usage_operations set window_key='day:2000-01-01' where user_id=${free}`;
      expect((await access.snapshot(free)).balances.advanced.remaining).toBe(
        initial.balances.advanced.limit,
      );
      const voice = newEntityId();
      const lease = await access.reserve(free, voice, "voice-v1", "voice", 60);
      await access.assertVoiceLease(free, voice);
      await runtime.database
        .sql`update app.usage_operations set expires_at=now()-interval '1 second' where user_id=${free} and operation_id=${voice}`;
      await expect(access.assertVoiceLease(free, voice)).rejects.toMatchObject({
        code: "VOICE_LEASE_EXPIRED",
      });
      expect((await access.snapshot(free)).balances.voice.used).toBe(lease.amount);
      expect((await access.reserve(free, voice, "voice-v1", "voice", 60)).replay).toBe(
        true,
      );
      expect((await access.snapshot(free)).balances.voice.used).toBe(lease.amount);
    });

    it("honors purchased feature flags and gives one internal repair per successful interaction", async () => {
      await runtime.database
        .sql`insert into app.entitlement_grants(id,user_id,plan_id,entitlement_key,environment,source_provider,source_reference_id,status,provider_event_at)
      values (${newEntityId()},${free},'pro','subscription','test','manual',${newEntityId()},'active',now())`;
      const paid = await access.snapshot(free);
      expect(paid.policy.plan).toBe("max");
      expect(paid.policy.friendSlotLimit).toBe(30);
      const original = newEntityId(),
        repair = newEntityId();
      await access.reserve(free, original, "original", "chat");
      await access.settle(free, original, true, { content: "reply" });
      const before = await access.snapshot(free);
      await access.reserve(free, repair, "repair", "auxiliary", 1, original);
      await access.settle(free, repair, true, { content: "better reply" });
      expect((await access.snapshot(free)).balances.chat.remaining).toBe(
        before.balances.chat.remaining,
      );
      await expect(
        access.reserve(free, newEntityId(), "repair-again", "auxiliary", 1, original),
      ).rejects.toMatchObject({ code: "REPAIR_NOT_ALLOWED" });
      await expect(
        access.reserve(guest, newEntityId(), "stolen", "auxiliary", 1, original),
      ).rejects.toMatchObject({ code: "REPAIR_NOT_ALLOWED" });
    });
  },
);
