import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { integrationConfig } from "../helpers/integration.js";
import { generationFixture } from "../helpers/learning-generation.js";
import { LearningGenerationRepository } from "../../src/modules/learning/generation-repository.js";
import { createLearningGenerationProcessor } from "../../src/modules/learning/generation-processor.js";
import { contentHash } from "../../src/modules/learning/content.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "候选修订审计与复审",
  () => {
    let database: DatabaseResource;
    let repository: LearningGenerationRepository;
    const ids: string[] = [];
    const notes =
      "工程修订夹具：保留原始失败证据，调整候选内容后须重新独立解题及人工发布，不得跳过质量检查。";
    beforeAll(async () => {
      database = createDatabase(integrationConfig());
      await runMigrations(database);
      repository = new LearningGenerationRepository(database);
    });
    afterAll(async () => {
      for (const id of ids)
        await database.sql`delete from app.learning_generation_edits where source_job_id=${id} or revised_job_id=${id}`;
      for (const id of ids) {
        await database.sql`delete from app.learning_generation_runs where job_id=${id}`;
        await database.sql`delete from app.learning_generation_jobs where id=${id}`;
        await database.sql`delete from app.learning_unit_versions where unit_id=${`generated.${id}`}`;
        await database.sql`delete from app.learning_units where id=${`generated.${id}`}`;
      }
      await database.close();
    });
    async function failedDraft() {
      const id = randomUUID(),
        fixture = await generationFixture(id);
      fixture.blueprint = { ...fixture.blueprint, roleKey: `test.${id}` };
      fixture.unit.roleKey = fixture.blueprint.roleKey;
      ids.push(id);
      await database.sql`insert into app.learning_generation_jobs(id,role_key,level_key) values(${id},${fixture.blueprint.roleKey},'primary3')`;
      const lease = await repository.claim([fixture.blueprint], 50);
      if (!lease) throw new Error("缺少测试租约。");
      await repository.recordCandidate(lease, fixture.unit);
      await repository.fail(lease, "TEST_REJECTED");
      await database.sql`update app.learning_generation_jobs set status='failed' where id=${id}`;
      const input = {
        requestId: randomUUID(),
        sourceJobId: id,
        candidateHash: contentHash(fixture.unit),
        editor: "工程编辑",
        notes,
        unit: fixture.unit,
      };
      return { id, fixture, input };
    }
    it("并发重复修订只建一个任务；原稿保留，重新盲审只调用一次供应商", async () => {
      const { id, fixture, input } = await failedDraft();
      const before = await repository.inspect(id);
      const revisions = await Promise.all([
        repository.revise(input, fixture.blueprint),
        repository.revise(input, fixture.blueprint),
      ]);
      const revised = revisions[0];
      if (!revised) throw new Error("缺少修订任务。");
      ids.push(revised);
      expect(revisions[1]).toBe(revised);
      await expect(
        repository.revise({ ...input, notes: notes + "改变" }, fixture.blueprint),
      ).rejects.toThrow();
      await expect(
        repository.revise({ ...input, requestId: randomUUID() }, fixture.blueprint),
      ).rejects.toThrow();
      expect((await repository.inspect(id)).candidate).toEqual(before.candidate);
      expect((await repository.inspect(id)).runs).toEqual(before.runs);
      expect((await repository.inspect(revised)).attempts).toBe(0);
      // 修订同样受公共预算约束，不绕过领取入口。
      expect(await repository.claim([fixture.blueprint], 1)).toBeUndefined();
      const complete = vi.fn(
        (request: {
          phase: "author" | "review";
          messages: readonly { content: string }[];
        }) => {
          expect(request.phase).toBe("review");
          const data = JSON.parse(request.messages[1]?.content ?? "{}") as {
            questions: Record<string, unknown>[];
          };
          expect(
            data.questions.every(
              (q) =>
                !("answer" in q) && !("acceptedAnswers" in q) && !("explanation" in q),
            ),
          ).toBe(true);
          return Promise.resolve({
            content: JSON.stringify(fixture.report),
            model: "工程复审",
            usage: { inputTokens: 10, outputTokens: 10 },
          });
        },
      );
      expect(
        await createLearningGenerationProcessor(
          repository,
          [fixture.blueprint],
          complete,
          50,
        ).runOnce(),
      ).toBe("review");
      expect(complete).toHaveBeenCalledTimes(1);
      const job = await repository.inspect(revised);
      expect(job.edits).toHaveLength(1);
      expect(job.runs[0]).toMatchObject({
        author_model: null,
        review_model: "工程复审",
      });
      expect(job.candidate).toMatchObject({
        id: `generated.${revised}`,
        authorship: { kind: "generated" },
      });
      await repository.publish(
        revised,
        String(job.candidate_hash),
        fixture.blueprint,
        "工程审核",
        notes,
      );
      expect((await repository.inspect(revised)).status).toBe("published");
      await expect(
        repository.revise(
          {
            ...input,
            requestId: randomUUID(),
            sourceJobId: revised,
            candidateHash: String(job.candidate_hash),
            unit: job.candidate,
          },
          fixture.blueprint,
        ),
      ).rejects.toThrow();
    });
    it("错误原稿哈希、跨角色与课程蓝图漂移均阻止修订或复审", async () => {
      const { fixture, input } = await failedDraft();
      await expect(
        repository.revise(
          { ...input, candidateHash: "0".repeat(64) },
          fixture.blueprint,
        ),
      ).rejects.toThrow();
      await expect(
        repository.revise(
          { ...input, unit: { ...fixture.unit, roleKey: "other" } },
          fixture.blueprint,
        ),
      ).rejects.toThrow();
      const revised = await repository.revise(input, fixture.blueprint);
      ids.push(revised);
      const complete = vi.fn();
      expect(
        await createLearningGenerationProcessor(
          repository,
          [{ ...fixture.blueprint, hash: "1".repeat(64) }],
          complete,
          50,
        ).runOnce(),
      ).toBe("idle");
      expect(complete).not.toHaveBeenCalled();
      expect((await repository.inspect(revised)).last_error_code).toBe(
        "EDITOR_BLUEPRINT_CHANGED",
      );
    });
    it("人工修订仍会因新审题不通过而失败，不能直接发布", async () => {
      const { fixture, input } = await failedDraft();
      const revised = await repository.revise(input, fixture.blueprint);
      ids.push(revised);
      fixture.report.levelFits = false;
      const complete = vi.fn(() =>
        Promise.resolve({
          content: JSON.stringify(fixture.report),
          model: "工程否决",
          usage: {},
        }),
      );
      expect(
        await createLearningGenerationProcessor(
          repository,
          [fixture.blueprint],
          complete,
          50,
        ).runOnce(),
      ).toBe("failed");
      const job = await repository.inspect(revised);
      expect(job.last_error_code).toBe("INDEPENDENT_REVIEW_FAILED");
      expect(job.runs[0]?.review_report).toMatchObject({ levelFits: false });
      await expect(
        repository.publish(
          revised,
          String(job.candidate_hash),
          fixture.blueprint,
          "工程审核",
          notes,
        ),
      ).rejects.toThrow();
    });
  },
);
