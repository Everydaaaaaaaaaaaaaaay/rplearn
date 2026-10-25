import type { LearningAudioAsset } from "../../src/modules/learning/audio.js";
import type { LearningImageAsset } from "../../src/modules/learning/images.js";
import { readFile } from "node:fs/promises";
import { buildApp } from "../../src/app.js";
import { createAdminAuthenticator } from "../../src/modules/admin/http.js";
import { registerLearningAdminRoutes } from "../../src/modules/learning/admin-routes.js";
import { LearningAdminService } from "../../src/modules/learning/admin-service.js";
import { LearningAdminRepository } from "../../src/modules/learning/admin-repository.js";
import { LearningGenerationRepository } from "../../src/modules/learning/generation-repository.js";
import { randomUUID } from "node:crypto";
import { learningPolicy } from "../../src/modules/learning/policy.js";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  LearningEngineRepository,
  type LearningSession,
} from "../../src/modules/learning/engine-repository.js";
import { LearningBankRepository } from "../../src/modules/learning/bank-repository.js";
import { loadBankCatalog } from "../../src/modules/learning/bank-catalog.js";
import { loadCuratedCatalog } from "../../src/modules/learning/catalog.js";
import {
  bankIdentity,
  bankQuestionSchema,
} from "../../src/modules/learning/bank-content.js";
import {
  contentHash,
  type LearningLevel,
  type LearningUnit,
} from "../../src/modules/learning/content.js";
import { gradeAnswer } from "../../src/modules/learning/grading.js";
import { questionForPresentation } from "../../src/modules/learning/presentation.js";
import { integrationConfig } from "../helpers/integration.js";

function required<T>(value: T | undefined | null): T {
  if (value === undefined || value === null) throw new Error("测试夹具缺少必要内容。");
  return value;
}

const directory = new URL("../../config/learning", import.meta.url).pathname;
describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")("公共题库事务", () => {
  let db: DatabaseResource,
    engine: LearningEngineRepository,
    bank: LearningBankRepository;
  let catalog: Awaited<ReturnType<typeof loadBankCatalog>>;
  let authored: Awaited<ReturnType<typeof loadCuratedCatalog>>;
  const users: string[] = [];
  const addedIds: string[] = [];
  const addedUnits: LearningUnit[] = [];
  beforeAll(async () => {
    db = createDatabase(integrationConfig());
    await runMigrations(db);
    engine = new LearningEngineRepository(db);
    bank = new LearningBankRepository(db);
    authored = await loadCuratedCatalog(directory);
    catalog = await loadBankCatalog(directory);
    await engine.publishBatch(
      authored.units,
      authored.audioAssets.map((a) => a.metadata),
      authored.imageAssets.map((a) => a.metadata),
    );
    await bank.importCatalog(catalog.entries, catalog.blueprints);
  }, 30000);
  afterAll(async () => {
    for (const user of users) await db.sql`delete from app.users where id=${user}`;
    const ids = [...catalog.entries.map((e) => e.question.id), ...addedIds];
    await db.sql`delete from app.learning_bank_audit where question_id=any(${ids})`;
    await db.sql`delete from app.learning_bank_sources where question_id=any(${ids})`;
    await db.sql`delete from app.learning_bank_versions where question_id=any(${ids})`;
    await db.sql`delete from app.learning_bank_questions where id=any(${ids})`;
    await db.sql`delete from app.learning_bank_blueprints where id=any(${catalog.blueprints.map((b) => b.id)})`;
    for (const unit of [...authored.units, ...addedUnits]) {
      await db.sql`delete from app.learning_unit_versions where unit_id=${unit.id}`;
      await db.sql`delete from app.learning_units where id=${unit.id}`;
    }
    await db.close();
  });
  async function account() {
    const user = randomUUID();
    users.push(user);
    await db.sql`insert into app.users(id) values(${user})`;
    const command = <T>(action: (s: LearningSession) => Promise<T>) =>
      engine.command(user, randomUUID(), "test", {}, action);
    async function character(role = `character.${randomUUID()}`) {
      const id = randomUUID();
      const state = await command((s) => s.ensureCharacter(id, role));
      await command((s) =>
        s.recordMessage({
          characterId: id,
          cycleId: state.cycleId,
          messageId: randomUUID(),
          text: "字".repeat(1000),
        }),
      );
      return id;
    }
    async function start(id: string, level: LearningLevel = "primary3") {
      const r = await command((s) => s.start(id, level));
      if (!r.attempt) throw new Error("未分配挑战");
      return r.attempt;
    }
    return { user, command, character, start };
  }
  async function privateUnit(id: string) {
    const [r] = await db.sql<
      { payload: LearningUnit }[]
    >`select coalesce(a.snapshot,v.payload) as payload from app.learning_attempts a left join app.learning_unit_versions v on v.unit_id=a.unit_id and v.version=a.unit_version where a.id=${id}`;
    return required(r).payload;
  }
  it("旧中文听力快照通过真实读取链路显示英文，存储和原答案保持不变", async () => {
    const c = await account();
    const attempt = await c.start(await c.character());
    const frozen = await privateUnit(attempt.id);
    const original = required(
      authored.units.find((u) => u.id === "companion.senior3.paper-boat")?.questions[0],
    );
    if (original.type !== "listeningChoice")
      throw new Error("Missing listening fixture");
    const old = {
      ...original,
      id: required(frozen.questions[0]).id,
      prompt: "听两人商量旧书交换活动。第二位说话人最后支持什么安排？",
      options: [
        { id: "a", text: "取消活动，因为下午也缺少帮手。" },
        { id: "b", text: "保留活动，建议改到午饭后进行。" },
        { id: "c", text: "保留活动，仍按周六上午安排。" },
      ],
    };
    frozen.questions[0] = old;
    frozen.goalIds = [...new Set([...frozen.goalIds, old.goalId])];
    await db.sql`update app.learning_attempts set snapshot=${JSON.stringify(frozen)}::jsonb where id=${attempt.id}`;
    const hash = contentHash(await privateUnit(attempt.id));
    const shown = await engine.read(c.user, (s) => s.attempt(attempt.id));
    expect(shown.unit.questions[0]?.prompt).toBe(original.prompt);
    expect(shown.unit.questions[0]).toMatchObject({ options: original.options });
    const speech = await engine.read(c.user, (s) =>
      s.listeningScript(attempt.id, old.id, old.audio.assetId),
    );
    expect(speech.segments.at(-1)?.text).toBe(`Question: ${original.prompt}`);
    expect(gradeAnswer(old, { kind: "choice", optionId: "b" }).outcome).toBe("correct");
    expect(contentHash(await privateUnit(attempt.id))).toBe(hash);
  });
  it("任意角色覆盖已发布档位，固定快照可读取且响应没有答案", async () => {
    const c = await account();
    for (const level of new Set(catalog.blueprints.map((b) => b.level))) {
      const id = await c.character();
      if (/^senior[123]$/.test(level)) {
        expect(
          (await c.command((s) => s.start(id, level, { completeGroups: true }))).status,
        ).toBe("preparing");
        continue;
      }
      const a = await c.start(id, level);
      const hasLongUnit = [
        "senior1",
        "senior2",
        "senior3",
        "undergraduate",
        "postgraduate",
        "advanced",
      ].includes(level);
      expect(a.unit.questions).toHaveLength(hasLongUnit ? 18 : 6);
      if (hasLongUnit) {
        expect(a.unit.beats).toHaveLength(3);
        expect(a.unit.beats.every((beat) => beat.afterQuestion === 0)).toBe(true);
      }
      expect(a.unit.level).toBe(level);
      expect(JSON.stringify(a.unit)).not.toContain('"acceptedAnswers"');
      expect(JSON.stringify(a.unit)).not.toContain('"explanation"');
      expect((await engine.read(c.user, (s) => s.history(id, 10))).items[0]?.id).toBe(
        a.id,
      );
    }
  });
  it("主角色同样优先进入已发布十八题新单元及完整开场", async () => {
    for (const role of ["oliver", "ruby", "marcus"]) {
      for (const level of ["undergraduate", "postgraduate", "advanced"] as const) {
        const c = await account();
        const a = await c.start(await c.character(role), level);
        expect(a.unit.questions, `${role}/${level}`).toHaveLength(18);
        expect(a.unit.beats).toHaveLength(3);
        expect(a.unit.beats.every((beat) => beat.afterQuestion === 0)).toBe(true);
        expect(a.unit.id).toMatch(/^assembled\./);
      }
    }
  });
  it("四级正式十八题包含完整开场，补答仅补得分且跨角色不重复出题", async () => {
    const c = await account();
    const character = await c.character();
    const a = await c.start(character, "undergraduate");
    const frozen = await privateUnit(a.id);
    expect(a.unit.questions).toHaveLength(18);
    expect(a.unit.beats).toHaveLength(3);
    expect(a.unit.beats.every((beat) => beat.afterQuestion === 0)).toBe(true);
    expect(a.unit.beats).toEqual(frozen.beats);
    for (const q of frozen.questions.slice(0, 15))
      await c.command((s) =>
        s.submit({
          attemptId: a.id,
          roundId: a.round.id,
          questionId: q.id,
          answer: gradeAnswer(q, { kind: "skip" }).solution,
        }),
      );
    await c.command((s) => s.finish(a.id, true));
    expect((await engine.read(c.user, (s) => s.progress()))[0]?.points).toBe(15);
    const retry = await c.command((s) => s.retry(a.id));
    expect(retry.round.questionIds).toHaveLength(3);
    for (const q of frozen.questions.slice(15))
      await c.command((s) =>
        s.submit({
          attemptId: a.id,
          roundId: retry.round.id,
          questionId: q.id,
          answer: gradeAnswer(q, { kind: "skip" }).solution,
        }),
      );
    expect((await engine.read(c.user, (s) => s.progress()))[0]?.points).toBe(18);
    expect((await privateUnit(a.id)).beats).toEqual(frozen.beats);
    const next = await c.character();
    const second = await c.start(next, "undergraduate");
    expect(second.unit.questions).toHaveLength(18);
    const firstIds = new Set(a.unit.questions.map((q) => q.id));
    expect(second.unit.questions.every((q) => !firstIds.has(q.id))).toBe(true);
    expect(second.unit.beats).toHaveLength(3);
    const exhausted = await c.character();
    expect(await c.command((s) => s.start(exhausted, "undergraduate"))).toEqual({
      status: "preparing",
      attempt: null,
    });
    expect((await engine.read(c.user, (s) => s.character(exhausted))).characters).toBe(
      learningPolicy.characterThreshold,
    );
    const other = await account();
    const reused = await other.start(await other.character(), "undergraduate");
    const seenByFirst = new Set([
      ...firstIds,
      ...second.unit.questions.map((q) => q.id),
    ]);
    expect(reused.unit.questions.every((q) => seenByFirst.has(q.id))).toBe(true);
  });
  it("高中公共库开关不能恢复旧专属题或十八题混合练习", async () => {
    const c = await account();
    const character = await c.character("oliver");
    try {
      for (const enabled of [false, true]) {
        await bank.setEnabled(enabled);
        const result = await c.command((s) =>
          s.start(character, "senior3", { completeGroups: true }),
        );
        expect(result.status).toBe("preparing");
        expect(result.attempt).toBeNull();
      }
    } finally {
      await bank.setEnabled(true);
    }
  });
  it("并发跨角色不重复出题，其他账号可以使用相同公共库", async () => {
    const c = await account();
    const ids = await Promise.all([c.character(), c.character()]);
    const attempts = await Promise.all(ids.map((id) => c.start(id)));
    const first = new Set(required(attempts[0]).unit.questions.map((q) => q.id));
    expect(required(attempts[1]).unit.questions.every((q) => !first.has(q.id))).toBe(
      true,
    );
    const other = await account();
    expect((await other.start(await other.character())).unit.questions).toHaveLength(6);
    await expect(
      engine.read(other.user, (s) => s.attempt(required(attempts[0]).id)),
    ).rejects.toMatchObject({ code: "LEARNING_ATTEMPT_NOT_FOUND" });
  });
  it("首轮、补答、重复提交共用首次得分，且补答保留原题版本", async () => {
    const c = await account();
    const character = await c.character();
    const a = await c.start(character);
    const unit = await privateUnit(a.id);
    const first = required(unit.questions[0]);
    await c.command((s) =>
      s.submit({
        attemptId: a.id,
        roundId: a.round.id,
        questionId: first.id,
        answer: gradeAnswer(first, { kind: "skip" }).solution,
      }),
    );
    await c.command((s) => s.finish(a.id, true));
    expect((await engine.read(c.user, (s) => s.character(character))).characters).toBe(
      0,
    );
    const detail = await bank.detail(first.id);
    const old = bankQuestionSchema.parse(detail.payload);
    await bank.save(
      old.id,
      detail.content_hash,
      {
        ...old,
        version: old.version + 1,
        question: {
          ...old.question,
          explanation: "只修正讲解，不改变旧挑战已经固定的题面与答案。",
        },
        reviewNotes:
          "逐题核对题干与答案保持原样，本次只修改解析措辞，确认适用水平与场景不发生变化。",
      },
      true,
      "隔离测试",
    );
    expect((await privateUnit(a.id)).questions[0]).toEqual(first);
    const retry = await c.command((s) => s.retry(a.id));
    expect(retry.round.questionIds).toHaveLength(5);
    for (const q of unit.questions.slice(1))
      await c.command((s) =>
        s.submit({
          attemptId: a.id,
          roundId: retry.round.id,
          questionId: q.id,
          answer: gradeAnswer(q, { kind: "skip" }).solution,
        }),
      );
    expect((await engine.read(c.user, (s) => s.progress()))[0]?.points).toBe(6);
    await expect(
      bank.save(old.id, detail.content_hash, { ...old, version: 2 }, true, "过期编辑"),
    ).rejects.toMatchObject({ code: "LEARNING_BANK_CONFLICT" });
  });
  it("专属单元优先且与公共题库共享去重；下架后不再组卷", async () => {
    const c = await account();
    const character = await c.character("oliver");
    const a = await c.start(character, "primary2");
    expect(a.unit.id).toMatch(/^oliver\./);
    const refs = await db.sql<
      { question_id: string }[]
    >`select question_id from app.learning_bank_exposures where attempt_id=${a.id}`;
    expect(refs).toHaveLength(6);
    const other = await c.start(await c.character(), "primary2");
    expect(
      other.unit.questions.every((q) => !refs.some((r) => r.question_id === q.id)),
    ).toBe(true);
    const q = required(
      catalog.entries.find((e) => e.question.level === "primary5"),
    ).question;
    await bank.save(
      q.id,
      contentHash(q),
      {
        ...q,
        version: 2,
        reviewNotes:
          "测试下架单道题后组卷配额不足时应停止抽取，而不是复用旧专属单元继续提供该题。",
      },
      false,
      "隔离测试",
    );
    const source = required(catalog.entries.find((e) => e.question.id === q.id));
    expect(
      (await bank.preview(`bank.${source.unitId}`, "character.preview")).missing,
    ).toBe(true);
  });
  it("七天到期复习不重复奖励，未到期不重新出题", async () => {
    const c = await account();
    for (let i = 0; i < 6; i++) {
      const a = await c.start(await c.character(), "primary2");
      const unit = await privateUnit(a.id);
      for (const q of unit.questions)
        await c.command((s) =>
          s.submit({
            attemptId: a.id,
            roundId: a.round.id,
            questionId: q.id,
            answer: gradeAnswer(q, { kind: "skip" }).solution,
          }),
        );
      await c.command((s) => s.finish(a.id, false));
    }
    const character = await c.character();
    expect(await c.command((s) => s.start(character, "primary2"))).toEqual({
      status: "preparing",
      attempt: null,
    });
    await db.sql`update app.learning_bank_exposures set created_at=now()-interval '8 days' where user_id=${c.user}`;
    await db.sql`update app.learning_bank_mastery set created_at=now()-interval '8 days' where user_id=${c.user}`;
    const review = await c.start(character, "primary2");
    expect(review.unit.title).toMatch(/^复习/);
    for (const q of (await privateUnit(review.id)).questions) {
      const result = await c.command((s) =>
        s.submit({
          attemptId: review.id,
          roundId: review.round.id,
          questionId: q.id,
          answer: gradeAnswer(q, { kind: "skip" }).solution,
        }),
      );
      expect(result.awardedPoints).toBe(0);
    }
    expect((await engine.read(c.user, (s) => s.progress()))[0]?.points).toBe(36);
    expect(
      (await engine.read(c.user, (s) => s.attempt(review.id))).correctQuestionIds,
    ).toHaveLength(6);
  });

  it("后台鉴权、筛选、预览、错误答案拒绝、新题发布和重复材料阻止", async () => {
    const token = "bank-isolated-test-token-at-least-thirty-two";
    const config = integrationConfig({
      ADMIN_API_ENABLED: "true",
      ADMIN_API_KEYS: `editor=${token}`,
    });
    const app = await buildApp(config, { logger: false });
    registerLearningAdminRoutes(
      app,
      createAdminAuthenticator(config.adminApiKeys),
      new LearningAdminService(
        new LearningAdminRepository(db),
        new LearningGenerationRepository(db),
        [],
      ),
    );
    await app.ready();
    const headers = { authorization: `Bearer ${token}` };
    const path = "/internal/admin/learning/bank";
    try {
      expect((await app.inject({ url: path + "/questions" })).statusCode).toBe(401);
      const list = await app.inject({
        url: path + "/questions?level=junior1&type=choice&limit=2",
        headers,
      });
      expect(list.statusCode).toBe(200);
      expect(
        list.json<{ items: { payload: unknown; content_hash: string }[] }>().items,
      ).toHaveLength(2);
      const item = required(
        list.json<{ items: { payload: unknown; content_hash: string }[] }>().items[0],
      );
      const q = bankQuestionSchema.parse(item.payload);
      q.question = questionForPresentation(q.question);
      if (q.question.type !== "choice") throw new Error("夹具题型错误");
      const hash = item.content_hash;
      const invalid = {
        ...q,
        version: q.version + 1,
        question: { ...q.question, answer: "missing-option" },
      };
      expect(
        (
          await app.inject({
            method: "POST",
            url: path + "/questions/" + q.id,
            headers,
            payload: {
              expectedHash: hash,
              question: invalid,
              published: true,
              confirmed: true,
            },
          })
        ).statusCode,
      ).toBe(422);
      const variant = {
        ...q,
        question: {
          ...q.question,
          prompt: q.question.prompt + " (New isolated test material.)",
        },
      };
      const response = await app.inject({
        method: "POST",
        url: path + "/questions/" + q.id + "/variants",
        headers,
        payload: { expectedHash: hash, question: variant, confirmed: true },
      });
      expect(response.statusCode).toBe(200);
      addedIds.push(response.json<{ id: string }>().id);
      expect(
        (
          await app.inject({
            method: "POST",
            url: path + "/questions/" + q.id + "/variants",
            headers,
            payload: { expectedHash: hash, question: variant, confirmed: true },
          })
        ).statusCode,
      ).toBe(409);
      const preview = await app.inject({
        url:
          path +
          "/preview/" +
          required(catalog.blueprints.find((b) => b.level === "junior1")).id,
        headers,
      });
      expect(preview.statusCode).toBe(200);
      expect(
        preview.json<{ unit: { questions: unknown[] } }>().unit.questions,
      ).toHaveLength(6);
    } finally {
      await app.close();
    }
  });
  it("互斥修订持久化并用于新组卷，已有挑战仍保留原快照", async () => {
    const existing = await account();
    const characterId = await existing.character();
    const attempt = await existing.start(characterId, "advanced");
    const snapshot = await privateUnit(attempt.id);
    const entries = catalog.entries.filter(
      (entry) => entry.question.level === "advanced",
    );
    // 将该档候选临时登记为同一互斥组，验证不能绕过约束拼出新卷。
    for (const entry of entries) {
      const detail = await bank.detail(entry.question.id);
      const current = bankQuestionSchema.parse(detail.payload);
      await bank.save(
        current.id,
        detail.content_hash,
        {
          ...current,
          version: current.version + 1,
          exclusionGroupIds: ["test.shared-answer"],
        },
        true,
        "隔离互斥修订测试",
      );
    }
    const persisted = bankQuestionSchema.parse(
      (await bank.detail(required(entries[0]).question.id)).payload,
    );
    expect(persisted.exclusionGroupIds).toEqual(["test.shared-answer"]);
    const fresh = await account();
    const freshCharacter = await fresh.character();
    const result = await fresh.command((session) =>
      session.start(freshCharacter, "advanced"),
    );
    expect(result.status).toBe("preparing");
    expect(result.attempt).toBeNull();
    expect(await privateUnit(attempt.id)).toEqual(snapshot);
    expect((await existing.start(characterId, "advanced")).id).toBe(attempt.id);
  });
  it("目录修订与新题全量原子发布，失败回滚、重复幂等且不覆盖后续编辑", async () => {
    const original = required(authored.units.find((u) => u.level === "primary3"));
    const unit: LearningUnit = {
      ...structuredClone(original),
      id: "test.atomic-bank-unit",
      questions: original.questions.map((q) => ({
        ...q,
        prompt: q.prompt + "（原子发布隔离夹具）",
      })),
    };
    addedUnits.push(unit);
    await engine.publishBatch([unit], [], []);
    const entries = unit.questions.map((question) => ({
      unitId: unit.id,
      unitVersion: unit.version,
      localQuestionId: question.id,
      question: bankQuestionSchema.parse({
        ...required(catalog.entries[0]).question,
        id: bankIdentity(question),
        version: 1,
        level: unit.level,
        question,
        references: unit.references,
        exclusionGroupIds:
          question.id === unit.questions[0]?.id ? ["test.atomic-pair"] : [],
      }),
    }));
    addedIds.push(...entries.map((entry) => entry.question.id));
    const blueprint = {
      ...required(catalog.blueprints.find((b) => b.id === "bank." + original.id)),
      id: "bank.test.atomic-unit",
    };
    catalog.blueprints.push(blueprint);
    const old = await bank.detail(required(catalog.entries[0]).question.id);
    const revision = {
      expectedHash: old.content_hash,
      question: {
        ...old.payload,
        version: old.payload.version + 1,
        exclusionGroupIds: [
          ...(old.payload.exclusionGroupIds ?? []),
          "test.atomic-pair",
        ],
      },
    };
    // 在已修订旧题并插入若干新题后遇到无效来源，所有写入仍须回滚。
    const broken = entries.map((e, i) =>
      i === entries.length - 1 ? { ...e, unitId: "test.missing-unit" } : e,
    );
    await expect(
      bank.importCatalog(broken, [blueprint], [revision]),
    ).rejects.toMatchObject({ code: "LEARNING_BANK_CONFLICT" });
    expect((await bank.detail(old.payload.id)).content_hash).toBe(old.content_hash);
    for (const entry of entries)
      await expect(bank.detail(entry.question.id)).rejects.toMatchObject({
        code: "LEARNING_BANK_NOT_FOUND",
      });
    expect(
      await db.sql`select id from app.learning_bank_blueprints where id=${blueprint.id}`,
    ).toHaveLength(0);
    await expect(
      bank.importCatalog(
        entries,
        [blueprint],
        [{ ...revision, expectedHash: "0".repeat(64) }],
      ),
    ).rejects.toMatchObject({ code: "LEARNING_BANK_CONFLICT" });
    await bank.importCatalog(entries, [blueprint], [revision]);
    expect((await bank.detail(old.payload.id)).payload).toEqual(revision.question);
    expect(
      (await bank.detail(required(entries[0]).question.id)).payload.exclusionGroupIds,
    ).toEqual(["test.atomic-pair"]);
    for (const entry of entries)
      expect((await bank.detail(entry.question.id)).published).toBe(true);
    const audit = (await bank.detail(old.payload.id)).audit;
    await bank.importCatalog(entries, [blueprint], [revision]);
    expect((await bank.detail(old.payload.id)).audit).toEqual(audit);
    const fresh = await bank.detail(old.payload.id);
    const newer = {
      ...fresh.payload,
      version: fresh.payload.version + 1,
      question: {
        ...fresh.payload.question,
        explanation: "发布后人工修订的解析必须保留，旧发布包不得覆盖这次更新。",
      },
    };
    await bank.save(newer.id, fresh.content_hash, newer, true, "隔离后续编辑");
    await bank.setEnabled(false);
    await expect(
      bank.importCatalog(entries, [blueprint], [revision]),
    ).rejects.toMatchObject({ code: "LEARNING_BANK_CONFLICT" });
    expect((await bank.detail(newer.id)).payload).toEqual(newer);
    const [control] = await db.sql<
      { enabled: boolean }[]
    >`select enabled from app.learning_bank_control where id=true`;
    expect(control?.enabled).toBe(false);
  });
  it("非高中冻结原创整组进入真实事务、跨旅伴不重抽，未知填空不写错答", async () => {
    const manifest = JSON.parse(
      await readFile(`${directory}/originals/catalog.json`, "utf8"),
    ) as {
      units: { unit: LearningUnit }[];
      audioAssets: LearningAudioAsset[];
      imageAssets: LearningImageAsset[];
    };
    const selected = [
      ...new Set(manifest.units.map((e: { unit: LearningUnit }) => e.unit.level)),
    ]
      .filter((level) => !/^senior[123]$/.test(level))
      .map(
        (level) =>
          required(
            manifest.units.find((e: { unit: LearningUnit }) => e.unit.level === level),
          ).unit,
      );
    const grammar = required(
      manifest.units.find(
        (e: { unit: LearningUnit }) =>
          e.unit.id === "original.grade7-grammar-soup-saturday",
      ),
    ).unit;
    selected.push(grammar);
    addedUnits.push(...selected);
    const audioIDs = new Set(
      selected.flatMap((u) =>
        u.questions.flatMap((q) => ("audio" in q && q.audio ? [q.audio.assetId] : [])),
      ),
    );
    const imageIDs = new Set(
      selected.flatMap((u) =>
        u.questions.flatMap((q) => [
          ...(q.materialImages ?? []).map((m) => m.assetId),
          ...(q.type === "choice" || q.type === "listeningChoice"
            ? q.options.flatMap((o) => (o.imageAssetId ? [o.imageAssetId] : []))
            : []),
        ]),
      ),
    );
    await engine.publishBatch(
      selected,
      manifest.audioAssets.filter((a: { id: string }) => audioIDs.has(a.id)),
      manifest.imageAssets.filter((a: { id: string }) => imageIDs.has(a.id)),
    );
    const c = await account();
    for (const unit of selected.filter((u) => u.id !== grammar.id)) {
      const id = await c.character();
      const started = await c.command((s) =>
        s.start(id, unit.level, { completeGroups: true, originalUnitId: unit.id }),
      );
      const attempt = required(started.attempt);
      expect(attempt.unit.questions).toHaveLength(unit.questions.length);
      expect(
        attempt.unit.questions.every(
          (q) => q.material === unit.originalGroup?.material,
        ),
      ).toBe(true);
      expect(attempt.unit.beats).toEqual([]);
      expect(JSON.stringify(attempt.unit)).not.toContain("acceptedAnswers");
      const q = required(unit.questions[0]);
      const receipt = await c.command((s) =>
        s.submit({
          attemptId: attempt.id,
          roundId: attempt.round.id,
          questionId: q.id,
          answer: gradeAnswer(q, { kind: "skip" }).solution,
        }),
      );
      expect(receipt.awardedPoints).toBe(1);
      expect(receipt.attempt.round.answers).toHaveLength(1);
      const beforeJobs =
        await db.sql`select id from app.learning_generation_jobs where role_key='oliver' and level_key=${unit.level}`;
      const other = await c.character("oliver");
      expect(
        (
          await c.command((s) =>
            s.start(other, unit.level, {
              completeGroups: true,
              originalUnitId: unit.id,
            }),
          )
        ).attempt,
      ).toBeNull();
      const afterJobs =
        await db.sql`select id from app.learning_generation_jobs where role_key='oliver' and level_key=${unit.level}`;
      expect(afterJobs.length).toBe(beforeJobs.length);
    }
    const id = await c.character();
    const attempt = required(
      (
        await c.command((s) =>
          s.start(id, grammar.level, {
            completeGroups: true,
            originalUnitId: grammar.id,
          }),
        )
      ).attempt,
    );
    await expect(
      c.command((s) =>
        s.submit({
          attemptId: attempt.id,
          roundId: attempt.round.id,
          questionId: required(grammar.questions[0]).id,
          answer: { kind: "text", text: "unknownform" },
        }),
      ),
    ).rejects.toMatchObject({ code: "LEARNING_ANSWER_REVIEW_REQUIRED" });
    const fresh = await engine.read(c.user, (s) => s.attempt(attempt.id));
    expect(fresh.revision).toBe(attempt.revision);
    expect(fresh.round.answers).toEqual([]);
  }, 30000);
});
