import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { contentHash, unitSchema } from "../../src/modules/learning/content.js";
import {
  LearningEngineRepository,
  type LearningSession,
} from "../../src/modules/learning/engine-repository.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "精确绑定评分修订保留历史事务",
  () => {
    const user = randomUUID(),
      character = randomUUID();
    const raw = JSON.parse(
      readFileSync(
        new URL(
          "../../config/learning/expansions/2026-10-28/b005.json",
          import.meta.url,
        ),
        "utf8",
      ),
    ) as { entries: { unit: unknown }[] };
    const original = raw.entries
      .map((entry) => unitSchema.parse(entry.unit))
      .find(
        (unit) =>
          unit.id === "expansion.20261028.primary6.courtesy-grammar-workshop-005",
      );
    if (!original) throw new Error("Missing frozen slow fixture");
    const unit = unitSchema.parse({
      ...original,
      id: `test.grading-revision.${randomUUID()}`,
      questions: original.questions.map((question) => ({
        ...question,
        id: `${question.id}.remapped`,
      })),
    });
    const question = unit.questions.find((q) => q.id.endsWith(".q4.remapped"));
    if (question?.type !== "completion") throw new Error("Missing slow completion");
    const target = question;
    let db: DatabaseResource, engine: LearningEngineRepository;
    beforeAll(async () => {
      db = createDatabase(integrationConfig());
      await runMigrations(db);
      engine = new LearningEngineRepository(db);
      await db.sql`insert into app.users(id) values(${user})`;
      await engine.publish(unit);
    });
    afterAll(async () => {
      await db.sql`delete from app.users where id=${user}`;
      await db.sql`delete from app.learning_unit_versions where unit_id=${unit.id}`;
      await db.sql`delete from app.learning_units where id=${unit.id}`;
      await db.close();
    });

    it("旧错答及收据原样重放，新补答接受slow且只奖励一次，冻结版本不变", async () => {
      const command = <T>(action: (session: LearningSession) => Promise<T>) =>
        engine.command(user, randomUUID(), "revision-test", {}, action);
      const state = await command((s) => s.ensureCharacter(character, "companion"));
      await command((s) => s.debugFill(character, state.cycleId));
      const started = await command((s) =>
        s.start(character, "primary6", {
          completeGroups: true,
          originalUnitId: unit.id,
        }),
      );
      const attempt = started.attempt;
      if (!attempt) throw new Error("Missing isolated frozen practice");
      const input = {
        attemptId: attempt.id,
        roundId: attempt.round.id,
        questionId: target.id,
        answer: { kind: "text" as const, text: "slow" },
      };
      const historicalResult = {
        outcome: "incorrect",
        explanation: target.explanation,
        solution: { kind: "text", text: "slowly" },
      };
      // Represent an already committed pre-fix answer, without invoking today's grader.
      await db.sql`insert into app.learning_answers(round_id,question_id,answer,result) values(${input.roundId},${input.questionId},${JSON.stringify(input.answer)}::jsonb,${JSON.stringify(historicalResult)}::jsonb)`;
      await db.sql`update app.learning_attempts set revision=revision+1 where id=${attempt.id}`;
      const historicalResponse = {
        result: historicalResult,
        awardedPoints: 0,
        currentLevel: "primary6",
        automaticPromotion: null,
        attempt: await engine.read(user, (s) => s.attempt(attempt.id)),
        progress: [],
      };
      const requestId = randomUUID();
      await db.sql`insert into app.learning_receipts(user_id,request_id,operation,request_hash,response) values(${user},${requestId},'answer',${contentHash(input)},${JSON.stringify(historicalResponse)}::jsonb)`;
      const historic = async () =>
        contentHash(
          await db.sql`select answer,result from app.learning_answers where round_id=${input.roundId} and question_id=${target.id}`,
        );
      const receipt = async () =>
        contentHash(
          await db.sql`select operation,request_hash,response from app.learning_receipts where user_id=${user} and request_id=${requestId}`,
        );
      const beforeAnswer = await historic(),
        beforeReceipt = await receipt();
      expect(
        await engine.command(user, requestId, "answer", input, (s) => s.submit(input)),
      ).toEqual(historicalResponse);
      expect(await engine.read(user, (s) => s.progress())).toEqual([]);
      await command((s) => s.finish(attempt.id, true));
      const retry = await command((s) => s.retry(attempt.id));
      const corrected = { ...input, roundId: retry.round.id },
        correctedRequest = randomUUID();
      const submit = () =>
        engine.command(user, correctedRequest, "answer", corrected, (s) =>
          s.submit(corrected),
        );
      const first = await submit();
      expect(first.result.outcome).toBe("correct");
      expect(first.result.explanation).toContain("walk slow/slowly");
      expect(first.awardedPoints).toBe(1);
      expect(first.currentLevel).toBe("primary6");
      expect(await submit()).toEqual(first);
      expect(await historic()).toBe(beforeAnswer);
      expect(await receipt()).toBe(beforeReceipt);
      expect(await engine.read(user, (s) => s.progress())).toEqual([
        expect.objectContaining({ level: "primary6", points: 1 }),
      ]);
      const rewards =
        await db.sql`select points from app.learning_rewards where attempt_id=${attempt.id}`;
      expect(rewards).toEqual([{ points: 1 }]);
      const [frozen] = await db.sql<
        { payload: unknown }[]
      >`select payload from app.learning_unit_versions where unit_id=${unit.id} and version=${unit.version}`;
      expect(contentHash(frozen?.payload)).toBe(contentHash(unit));
      expect(unit.questions.find((q) => q.id === target.id)).toEqual(target);
    });
  },
);
