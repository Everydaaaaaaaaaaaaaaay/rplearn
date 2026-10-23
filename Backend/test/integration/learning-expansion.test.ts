import { randomUUID } from "node:crypto";
import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { LearningExpansionRepository } from "../../src/modules/learning/expansion-repository.js";
import { loadExpansionCatalog } from "../../src/modules/learning/expansion-catalog.js";
import { contentHash } from "../../src/modules/learning/content.js";
import { integrationConfig } from "../helpers/integration.js";
import { freshLearningFixture } from "../helpers/learning.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "新原创批次独立发布和一次撤回",
  () => {
    let db: DatabaseResource;
    let engine: LearningEngineRepository;
    let expansion: LearningExpansionRepository;
    const catalog = loadExpansionCatalog("b000");
    const users: string[] = [];
    const old = {
      ...freshLearningFixture("test.expansion-old"),
      level: "primary2" as const,
    };
    beforeAll(async () => {
      db = createDatabase(integrationConfig());
      await runMigrations(db);
      engine = new LearningEngineRepository(db);
      expansion = new LearningExpansionRepository(db);
      await engine.publish(old);
    });
    afterAll(async () => {
      for (const id of users) await db.sql`delete from app.users where id=${id}`;
      for (const id of [old.id, ...catalog.units.map((u) => u.id)]) {
        await db.sql`delete from app.learning_unit_versions where unit_id=${id}`;
        await db.sql`delete from app.learning_units where id=${id}`;
      }
      await db.close();
    });

    async function account(unitId: string) {
      const user = randomUUID(),
        character = randomUUID();
      users.push(user);
      await db.sql`insert into app.users(id) values(${user})`;
      const command = (action: Parameters<LearningEngineRepository["command"]>[4]) =>
        engine.command(user, randomUUID(), "test", {}, action);
      await command((s) => s.ensureCharacter(character, "oliver"));
      await db.sql`update app.learning_characters set characters=500 where user_id=${user}`;
      const result = await engine.command(user, randomUUID(), "start", {}, (s) =>
        s.start(character, "primary2", {
          completeGroups: true,
          originalUnitId: unitId,
        }),
      );
      if (!result.attempt) throw new Error("Missing test attempt");
      return { user, character, attempt: result.attempt };
    }

    it("只发布新命名空间并按批次哈希确认", async () => {
      await expect(expansion.publish("0".repeat(64), "b000")).rejects.toThrow("hash");
      const result = await expansion.publish(catalog.hash, "b000");
      expect(result.units).toBe(3);
      expect(catalog.units.every((u) => u.id.startsWith("expansion.20261024."))).toBe(
        true,
      );
      expect(() => loadExpansionCatalog("b999")).toThrow("Unknown");
    });

    it("撤回整轮新题，旧题与作答积分保留、活动与历史补答均不再领奖", async () => {
      const first = catalog.units.find((u) => u.level === "primary2");
      if (!first) throw new Error("Missing authored primary2 unit");
      const a = await account(first.id);
      const b = await account(first.id);
      const oldAttempt = await account(old.id);
      const q = first.questions[0];
      if (q?.type !== "choice") throw new Error("Missing authored choice");
      const input = {
        attemptId: a.attempt.id,
        roundId: a.attempt.round.id,
        questionId: q.id,
        answer: { kind: "choice" as const, optionId: q.answer },
      };
      const receipt = await engine.command(a.user, randomUUID(), "answer", input, (s) =>
        s.submit(input),
      );
      expect(receipt.awardedPoints).toBe(1);
      await engine.command(a.user, randomUUID(), "finish", {}, (s) =>
        s.finish(a.attempt.id, true),
      );
      const before =
        await db.sql`select question_id,answer,result from app.learning_answers where round_id=${a.attempt.round.id} order by question_id`;
      const oldBefore =
        await db.sql`select v.payload,u.published from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where u.id=${old.id}`;
      await engine.publish({ ...first, version: 2, title: first.title + " revised" });
      const withdrawn = await expansion.withdraw();
      expect(withdrawn.withdrawnUnits).toBe(3);
      expect(withdrawn.changedPublishedHashes).toBe(1);
      expect(withdrawn.retiredAttempts).toBe(2);
      expect(
        contentHash(
          await db.sql`select question_id,answer,result from app.learning_answers where round_id=${a.attempt.round.id} order by question_id`,
        ),
      ).toBe(contentHash(before));
      expect(
        contentHash(
          await db.sql`select v.payload,u.published from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where u.id=${old.id}`,
        ),
      ).toBe(contentHash(oldBefore));
      expect((await engine.read(a.user, (s) => s.progress()))[0]?.points).toBe(1);
      expect(
        (await engine.read(b.user, (s) => s.character(b.character))).activeAttemptId,
      ).toBeNull();
      expect(
        (await engine.read(b.user, (s) => s.character(b.character))).characters,
      ).toBe(500);
      expect(
        (await engine.read(oldAttempt.user, (s) => s.character(oldAttempt.character)))
          .activeAttemptId,
      ).toBe(oldAttempt.attempt.id);
      await expect(
        engine.command(a.user, randomUUID(), "retry", {}, (s) => s.retry(a.attempt.id)),
      ).rejects.toMatchObject({ code: "LEARNING_PRACTICE_REPLACED" });
      await expect(
        engine.command(b.user, randomUUID(), "answer", input, (s) =>
          s.submit({ ...input, attemptId: b.attempt.id, roundId: b.attempt.round.id }),
        ),
      ).rejects.toMatchObject({ code: "LEARNING_PRACTICE_REPLACED" });
      expect(
        (await engine.read(a.user, (s) => s.attempt(a.attempt.id))).correctQuestionIds,
      ).toContain(q.id);
      expect(
        (await engine.read(b.user, (s) => s.originals("primary2"))).units,
      ).toHaveLength(0);
      expect((await expansion.withdraw()).withdrawnUnits).toBe(0);
      // Re-running publication does not silently reactivate a withdrawn immutable version.
      await expansion.publish(catalog.hash, "b000");
      expect(
        (await engine.read(b.user, (s) => s.originals("primary2"))).units,
      ).toHaveLength(0);
    });
  },
);
