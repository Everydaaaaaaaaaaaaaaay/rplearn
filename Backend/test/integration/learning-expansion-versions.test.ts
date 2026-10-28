import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { contentHash, unitSchema } from "../../src/modules/learning/content.js";
import {
  LearningEngineRepository,
  type LearningSession,
} from "../../src/modules/learning/engine-repository.js";
import { loadExpansionCatalog } from "../../src/modules/learning/expansion-catalog.js";
import { gradeAnswer } from "../../src/modules/learning/grading.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "新内容前向版本保留历史事务",
  () => {
    const source = loadExpansionCatalog("b058", false, "2026-10-28").units.find(
      (u) => u.level === "undergraduate",
    );
    if (!source) throw new Error("Missing frozen published text fixture");
    const first = unitSchema.parse({
      ...source,
      id: `test.forward-version.${randomUUID()}`,
    });
    const second = unitSchema.parse({
      ...first,
      version: 2,
      questions: first.questions.map((q) => {
        if (!q.material) throw new Error("Missing complete fixture material");
        return {
          ...q,
          material: q.material + "\nReviewed forward-revision engineering fixture.",
        };
      }),
    });
    const users: string[] = [];
    let db: DatabaseResource, engine: LearningEngineRepository;
    beforeAll(async () => {
      db = createDatabase(integrationConfig());
      await runMigrations(db);
      engine = new LearningEngineRepository(db);
      await engine.publish(first);
    });
    afterAll(async () => {
      for (const id of users) await db.sql`delete from app.users where id=${id}`;
      await db.sql`delete from app.learning_unit_versions where unit_id=${first.id}`;
      await db.sql`delete from app.learning_units where id=${first.id}`;
      await db.close();
    });
    async function account() {
      const user = randomUUID(),
        character = randomUUID();
      users.push(user);
      await db.sql`insert into app.users(id) values(${user})`;
      const command = <T>(action: (s: LearningSession) => Promise<T>) =>
        engine.command(user, randomUUID(), "version-test", {}, action);
      const state = await command((s) => s.ensureCharacter(character, "companion"));
      await command((s) => s.debugFill(character, state.cycleId));
      const start = () =>
        command((s) =>
          s.start(character, first.level, {
            completeGroups: true,
            originalUnitId: first.id,
          }),
        );
      return { user, character, command, start };
    }
    it("追加v2只改变新分配，旧版本、活动任务、答案、收据及奖励保持原样", async () => {
      const a = await account();
      const started = await a.start(),
        attempt = started.attempt,
        question = first.questions[0];
      if (!attempt || !question) throw new Error("Missing original attempt");
      const input = {
        attemptId: attempt.id,
        roundId: attempt.round.id,
        questionId: question.id,
        answer: gradeAnswer(question, { kind: "skip" }).solution,
      };
      const requestId = randomUUID();
      const answer = await engine.command(a.user, requestId, "answer", input, (s) =>
        s.submit(input),
      );
      expect(answer.awardedPoints).toBe(1);
      const storedHistory = async () =>
        contentHash({
          answers:
            await db.sql`select answer,result from app.learning_answers where round_id=${attempt.round.id}`,
          receipts:
            await db.sql`select operation,request_hash,response from app.learning_receipts where user_id=${a.user} and request_id=${requestId}`,
          rewards:
            await db.sql`select question_id,points from app.learning_rewards where attempt_id=${attempt.id}`,
          snapshot:
            await db.sql`select snapshot,unit_id,unit_version from app.learning_attempts where id=${attempt.id}`,
        });
      const before = await storedHistory();
      await engine.publish(second);
      await expect(
        engine.publish({ ...first, title: "Cannot overwrite version one" }),
      ).rejects.toMatchObject({ code: "LEARNING_IMMUTABLE_CONTENT" });
      await engine.publish(first); // Replaying a frozen older publication must not downgrade the current version.
      const rows = await db.sql<
        { version: number; payload: unknown; content_hash: string }[]
      >`select version,payload,content_hash from app.learning_unit_versions where unit_id=${first.id} order by version`;
      expect(rows.map((r) => r.version)).toEqual([1, 2]);
      expect(rows[0]?.content_hash).toBe(contentHash(first));
      expect(contentHash(rows[0]?.payload)).toBe(contentHash(first));
      expect(contentHash(rows[1]?.payload)).toBe(contentHash(second));
      const reopened = await a.start();
      expect(reopened.attempt?.id).toBe(attempt.id);
      expect(reopened.attempt?.unit.version).toBe(1);
      expect(reopened.attempt?.unit.questions[0]?.material).toBe(question.material);
      expect(
        await engine.command(a.user, requestId, "answer", input, (s) =>
          s.submit(input),
        ),
      ).toEqual(answer);
      expect(await storedHistory()).toBe(before);
      expect((await engine.read(a.user, (s) => s.progress()))[0]?.points).toBe(1);
      const b = await account();
      const latest = await b.start();
      expect(latest.attempt?.unit.version).toBe(2);
      expect(latest.attempt?.unit.questions[0]?.material).toBe(
        second.questions[0]?.material,
      );
    });
  },
);
