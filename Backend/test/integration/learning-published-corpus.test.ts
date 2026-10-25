import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import type { AuthService } from "../../src/modules/auth/service.js";
import {
  unitSchema,
  publicUnit,
  type LearningLevel,
  type LearningUnit,
} from "../../src/modules/learning/content.js";
import { gradeAnswer } from "../../src/modules/learning/grading.js";
import {
  gaokaoCatalog,
  isHighSchool,
  gaokaoPracticeFamily,
} from "../../src/modules/learning/gaokao-policy.js";
import { loadExpansionCatalog } from "../../src/modules/learning/expansion-catalog.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import {
  createLearningService,
  type LearningService,
} from "../../src/modules/learning/service.js";
import { registerLearningRoutes } from "../../src/modules/learning/routes.js";
import { integrationConfig } from "../helpers/integration.js";
import { learningImageSchema } from "../../src/modules/learning/images.js";
import { learningAudioSchema } from "../../src/modules/learning/audio.js";
import { z } from "zod";

type Attempt = Awaited<ReturnType<LearningService["attempt"]>>;

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "已发布完整题库逐组 HTTP 验收",
  () => {
    let db: DatabaseResource, app: FastifyInstance, engine: LearningEngineRepository;
    let units: LearningUnit[];
    let level: LearningLevel = "primary1";
    const user = randomUUID(),
      character = randomUUID();
    const headers = {
      authorization: "Bearer isolated-corpus-test",
      "x-learning-complete-groups": "1",
    };
    const output = process.env.LEARNING_CORPUS_OUTPUT;
    const report = {
      units: 0,
      responses: 0,
      retries: 0,
      families: {} as Record<string, number>,
      levels: {} as Record<string, number>,
    };

    beforeAll(async () => {
      db = createDatabase(integrationConfig());
      await runMigrations(db);
      engine = new LearningEngineRepository(db);
      const original = z
        .object({
          units: z.array(z.object({ unit: unitSchema })),
          imageAssets: z.array(learningImageSchema),
          audioAssets: z.array(learningAudioSchema),
        })
        .parse(
          JSON.parse(
            await readFile(
              new URL("../../config/learning/originals/catalog.json", import.meta.url),
              "utf8",
            ),
          ) as unknown,
        );
      const expansions = loadExpansionCatalog();
      units = [
        ...original.units
          .map((e: { unit: unknown }) => unitSchema.parse(e.unit))
          .filter((u: LearningUnit) => !isHighSchool(u.level)),
        ...expansions.units.filter((u) => !isHighSchool(u.level)),
        ...gaokaoCatalog().practices.map((p) => p.unit),
      ];
      const images = new Map<string, ReturnType<typeof learningImageSchema.parse>>(
        original.imageAssets.map((a: unknown) => {
          const image = learningImageSchema.parse(a);
          return [image.id, image];
        }),
      );
      for (const manifest of expansions.manifests)
        for (const image of manifest.imageAssets ?? []) images.set(image.id, image);
      const chart = learningImageSchema.parse(
        JSON.parse(
          await readFile(
            new URL("../../config/learning/gaokao/image.json", import.meta.url),
            "utf8",
          ),
        ) as unknown,
      );
      images.set(chart.id, chart);
      for (let i = 0; i < units.length; i += 25) {
        await engine.publishBatch(
          units.slice(i, i + 25),
          i === 0 ? original.audioAssets : undefined,
          i === 0 ? [...images.values()] : undefined,
        );
      }
      app = await buildApp(integrationConfig(), { logger: false });
      // Authentication itself is covered by learning-api.test.ts; all learning HTTP,
      // validation, selection, grading, persistence and rewards below are real.
      const auth = {
        authenticate: () =>
          Promise.resolve({
            userId: user,
            sessionId: randomUUID(),
            tokenVersion: 1,
          }),
      } as unknown as AuthService;
      registerLearningRoutes(
        app,
        auth,
        createLearningService(db, {
          profile: () => Promise.resolve(level),
          character: () => Promise.resolve("oliver"),
        }),
      );
      await app.ready();
      if (output) {
        await mkdir(output, { recursive: true });
        await writeFile(
          join(output, "public-units.json"),
          JSON.stringify(units.map((u) => publicUnit(u))),
        );
      }
    }, 60000);
    afterAll(async () => {
      await app.close();
      await db.sql`delete from app.users where id=${user}`;
      await db.close();
    });

    async function post(path: string, payload: object) {
      const result = await app.inject({ method: "POST", url: path, headers, payload });
      assert.equal(result.statusCode, 200, `${path}: ${result.body}`);
      return result;
    }

    it("每组可列出、按真实编号开启、逐题判分、保存续做、结束并补答", async () => {
      const checkedLevels = new Set<string>();
      for (const unit of units) {
        level = unit.level;
        await db.sql`insert into app.users(id) values(${user})`;
        try {
          if (!checkedLevels.has(level)) {
            const listing = await app.inject({
              url: `/v1/learning/originals?level=${level}`,
              headers,
            });
            assert.equal(listing.statusCode, 200);
            assert.deepEqual(
              listing
                .json<{ units: { id: string }[] }>()
                .units.map((u) => u.id)
                .sort(),
              units
                .filter((u) => u.level === level)
                .map((u) => u.id)
                .sort(),
            );
            checkedLevels.add(level);
          }
          await engine.command(user, randomUUID(), "test", {}, (s) =>
            s.ensureCharacter(character, "oliver"),
          );
          await db.sql`update app.learning_characters set characters=1000 where user_id=${user}`;
          const started = await post(`/v1/learning/characters/${character}/attempts`, {
            requestId: randomUUID(),
            originalUnitId: unit.id,
          });
          let attempt = started.json<{ attempt: Attempt }>().attempt;
          assert.equal(attempt.unit.id, unit.id);
          assert.equal(attempt.round.questionIds.length, unit.questions.length);
          const first = unit.questions[0];
          assert.ok(first);
          for (const q of unit.questions) {
            const solution = gradeAnswer(q, { kind: "skip" }).solution;
            assert.equal(
              gradeAnswer(q, solution).outcome,
              "correct",
              `${unit.id}/${q.id}`,
            );
            if (q.type === "choice" || q.type === "listeningChoice") {
              for (const option of q.options)
                assert.equal(
                  gradeAnswer(q, { kind: "choice", optionId: option.id }).outcome ===
                    "correct",
                  option.id === q.answer,
                );
            } else if (q.type === "completion") {
              for (const text of q.acceptedAnswers)
                assert.equal(gradeAnswer(q, { kind: "text", text }).outcome, "correct");
            }
            const receipt: { attempt: Attempt; result: { outcome: string } } = (
              await post(`/v1/learning/attempts/${attempt.id}/answers`, {
                requestId: randomUUID(),
                expectedRevision: attempt.revision,
                roundId: attempt.round.id,
                questionId: q.id,
                answer: q.id === first.id ? { kind: "skip" } : solution,
              })
            ).json<{ attempt: Attempt; result: { outcome: string } }>();
            assert.equal(
              receipt.result.outcome,
              q.id === first.id ? "skipped" : "correct",
            );
            attempt = receipt.attempt;
            report.responses++;
          }
          const saved = await app.inject({
            url: `/v1/learning/attempts/${attempt.id}`,
            headers,
          });
          assert.equal(saved.statusCode, 200);
          assert.equal(
            saved.json<Attempt>().round.answers.length,
            unit.questions.length,
          );
          attempt = (
            await post(`/v1/learning/attempts/${attempt.id}/finish`, {
              requestId: randomUUID(),
              expectedRevision: attempt.revision,
              skipRemaining: false,
            })
          ).json<Attempt>();
          assert.equal(attempt.round.completed, true);
          attempt = (
            await post(`/v1/learning/attempts/${attempt.id}/retries`, {
              requestId: randomUUID(),
              expectedRevision: attempt.revision,
            })
          ).json<Attempt>();
          assert.deepEqual(attempt.round.questionIds, [first.id]);
          const final = (
            await post(`/v1/learning/attempts/${attempt.id}/answers`, {
              requestId: randomUUID(),
              expectedRevision: attempt.revision,
              roundId: attempt.round.id,
              questionId: first.id,
              answer: gradeAnswer(first, { kind: "skip" }).solution,
            })
          ).json<{ attempt: Attempt }>().attempt;
          assert.equal(final.round.completed, true);
          assert.equal(final.correctQuestionIds.length, unit.questions.length);
          report.units++;
          report.retries++;
          report.levels[unit.level] = (report.levels[unit.level] ?? 0) + 1;
          const family = unit.originalGroup?.family ?? "legacy";
          report.families[family] = (report.families[family] ?? 0) + 1;
          if (report.units % 100 === 0)
            console.log(
              `Corpus verified: ${String(report.units)}/${String(units.length)} groups, ${String(report.responses)} responses`,
            );
        } finally {
          await db.sql`delete from app.users where id=${user}`;
        }
      }
      if (output)
        await writeFile(join(output, "report.json"), JSON.stringify(report, null, 2));
      console.log(JSON.stringify(report));
    }, 600000);

    it("高中连续自动抽题能切换实际任务类型，且未完成挑战保持原记录", async () => {
      level = "senior3";
      await db.sql`insert into app.users(id) values(${user})`;
      try {
        await engine.command(user, randomUUID(), "test", {}, (s) =>
          s.ensureCharacter(character, "oliver"),
        );
        let previous: string | undefined;
        for (let i = 0; i < 6; i++) {
          await db.sql`update app.learning_characters set characters=1000 where user_id=${user}`;
          const attempt = (
            await post(`/v1/learning/characters/${character}/attempts`, {
              requestId: randomUUID(),
            })
          ).json<{ attempt: Attempt }>().attempt;
          const family = gaokaoPracticeFamily(attempt.unit.id);
          assert.ok(family);
          assert.notEqual(family, previous);
          const resumed = (
            await post(`/v1/learning/characters/${character}/attempts`, {
              requestId: randomUUID(),
            })
          ).json<{ attempt: Attempt }>().attempt;
          assert.equal(resumed.id, attempt.id);
          await post(`/v1/learning/attempts/${attempt.id}/finish`, {
            requestId: randomUUID(),
            expectedRevision: attempt.revision,
            skipRemaining: true,
          });
          previous = family;
        }
      } finally {
        await db.sql`delete from app.users where id=${user}`;
      }
    }, 30000);
  },
);
