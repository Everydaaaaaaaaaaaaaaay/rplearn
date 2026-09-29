import { randomUUID } from "node:crypto";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  loadCuratedCatalog,
  type CuratedCatalog,
} from "../../src/modules/learning/catalog.js";
import {
  LearningEngineRepository,
  type LearningSession,
} from "../../src/modules/learning/engine-repository.js";
import { gradeAnswer } from "../../src/modules/learning/grading.js";
import { learningFixture } from "../helpers/learning.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "原创题库的真实事务链路",
  () => {
    let database: DatabaseResource;
    let repository: LearningEngineRepository;
    let catalog: CuratedCatalog;
    const users: string[] = [];
    const unitIds: string[] = [];
    const testRoles: string[] = [];
    beforeAll(async () => {
      database = createDatabase(integrationConfig());
      await runMigrations(database);
      repository = new LearningEngineRepository(database);
      catalog = await loadCuratedCatalog(
        fileURLToPath(new URL("../../config/learning/", import.meta.url)),
      );
    });
    afterAll(async () => {
      for (const user of users)
        await database.sql`delete from app.users where id=${user}`;
      for (const unit of unitIds) {
        await database.sql`delete from app.learning_unit_versions where unit_id=${unit}`;
        await database.sql`delete from app.learning_units where id=${unit}`;
      }
      for (const role of testRoles)
        await database.sql`delete from app.learning_generation_jobs where role_key=${role}`;
      await database.close();
    });

    it("整批版本冲突全部回滚；相同目录重复发布不增加版本", async () => {
      const first = learningFixture(`test.a.${randomUUID()}`);
      const conflict = learningFixture(`test.z.${randomUUID()}`);
      unitIds.push(first.id, conflict.id);
      await repository.publish(conflict);
      await expect(
        repository.publishBatch([first, { ...conflict, title: "同版本偷偷改写" }]),
      ).rejects.toMatchObject({ code: "LEARNING_IMMUTABLE_CONTENT" });
      expect(
        await database.sql`select id from app.learning_units where id=${first.id}`,
      ).toHaveLength(0);
      await repository.publishBatch([first, conflict]);
      await repository.publishBatch([conflict, first]);
      expect(
        await database.sql`select version from app.learning_unit_versions where unit_id in (${first.id},${conflict.id})`,
      ).toHaveLength(2);
    });

    it.each([
      "primary1",
      "primary2",
      "primary3",
      "primary4",
      "primary5",
      "primary6",
      "junior1",
      "junior2",
      "junior3",
      "senior1",
      "senior2",
      "senior3",
    ] as const)(
      "%s 的实际原创池可独立分配，补答不重复得分，耗尽保持满条",
      async (level) => {
        const namespace = randomUUID();
        // 使用真实教学内容，仅隔离身份，避免影响并行用例的角色池。
        const units = catalog.units
          .filter((unit) => unit.level === level)
          .map((unit) => ({
            ...unit,
            id: `test.${namespace}.${unit.id}`,
            roleKey: `test.${namespace}.${unit.roleKey}`,
          }));
        unitIds.push(...units.map((u) => u.id));
        testRoles.push(...new Set(units.map((u) => u.roleKey)));
        await repository.publishBatch(
          units,
          catalog.audioAssets.map((a) => a.metadata),
          catalog.imageAssets.map((a) => a.metadata),
        );
        await repository.publishBatch(
          units,
          catalog.audioAssets.map((a) => a.metadata),
          catalog.imageAssets.map((a) => a.metadata),
        );
        const user = randomUUID();
        users.push(user);
        await database.sql`insert into app.users(id) values(${user})`;
        const command = <T>(
          input: unknown,
          execute: (session: LearningSession) => Promise<T>,
          requestId = randomUUID(),
        ) => repository.command(user, requestId, "catalog-test", input, execute);
        for (const role of new Set(units.map((unit) => unit.roleKey))) {
          const character = randomUUID();
          await command({ character, role }, (s) => s.ensureCharacter(character, role));
          const fill = async () => {
            const state = await repository.read(user, (s) => s.character(character));
            const message = {
              characterId: character,
              cycleId: state.cycleId,
              messageId: randomUUID(),
              text: "测".repeat(1000),
            };
            await command(message, (s) => s.recordMessage(message));
          };
          const seen = new Set<string>();
          const expectedCount = units.filter((u) => u.roleKey === role).length;
          for (let i = 0; i < expectedCount; i++) {
            await fill();
            const started = await command({ start: character }, (s) =>
              s.start(character, level),
            );
            if (!started.attempt) throw new Error("原创题库分配失败。");
            const attempt = started.attempt;
            expect(attempt.unit.level).toBe(level);
            expect(seen.has(attempt.unit.id)).toBe(false);
            seen.add(attempt.unit.id);
            const unit = units.find((u) => u.id === attempt.unit.id);
            if (!unit) throw new Error("抽到了目录以外的单元。");
            const first = unit.questions[0];
            if (!first) throw new Error("缺少原创题。");
            const firstAnswer = {
              attemptId: attempt.id,
              roundId: attempt.round.id,
              questionId: first.id,
              answer: gradeAnswer(first, { kind: "skip" }).solution,
            };
            const requestId = randomUUID();
            expect(
              await command(firstAnswer, (s) => s.submit(firstAnswer), requestId),
            ).toMatchObject({ awardedPoints: 1 });
            expect(
              await command(firstAnswer, (s) => s.submit(firstAnswer), requestId),
            ).toMatchObject({ awardedPoints: 1 });
            await command({ finish: attempt.id }, (s) => s.finish(attempt.id, true));
            expect(
              await repository.read(user, (s) => s.character(character)),
            ).toMatchObject({ characters: 0, activeAttemptId: null });
            const retry = await command({ retry: attempt.id }, (s) =>
              s.retry(attempt.id),
            );
            expect(retry.round.questionIds).toHaveLength(5);
            for (const question of unit.questions.slice(1)) {
              const input = {
                attemptId: attempt.id,
                roundId: retry.round.id,
                questionId: question.id,
                answer: gradeAnswer(question, { kind: "skip" }).solution,
              };
              expect(await command(input, (s) => s.submit(input))).toMatchObject({
                awardedPoints: 1,
              });
            }
            expect(
              (await repository.read(user, (s) => s.attempt(attempt.id)))
                .correctQuestionIds,
            ).toHaveLength(6);
          }
          expect(seen.size).toBe(expectedCount);
          await fill();
          expect(
            await command({ start: character }, (s) => s.start(character, level)),
          ).toEqual({ status: "preparing", attempt: null });
          expect(
            (await repository.read(user, (s) => s.character(character))).characters,
          ).toBe(1000);
        }
        expect(await repository.read(user, (s) => s.progress())).toEqual([
          expect.objectContaining({ level, points: units.length * 6, stars: 0 }),
        ]);
        expect(
          await database.sql`select question_id from app.learning_rewards where user_id=${user}`,
        ).toHaveLength(units.length * 6);
      },
    );
  },
);
