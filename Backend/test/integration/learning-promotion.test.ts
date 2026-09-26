import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAuthService, type AuthService } from "../../src/modules/auth/service.js";
import { createAccountService } from "../../src/modules/account/service.js";
import {
  createDomainLearningContext,
  createDomainService,
} from "../../src/modules/domain/service.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import {
  createLearningService,
  createLearningMilestoneReader,
  type LearningService,
} from "../../src/modules/learning/service.js";
import { registerLearningRoutes } from "../../src/modules/learning/routes.js";
import { contentHash, type LearningUnit } from "../../src/modules/learning/content.js";
import { gradeAnswer } from "../../src/modules/learning/grading.js";
import { type PromotionCourse } from "../../src/modules/learning/promotion-content.js";
import { integrationConfig } from "../helpers/integration.js";
import { learningFixture } from "../helpers/learning.js";

type Promotion = Awaited<ReturnType<LearningService["promotion"]>>;
describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")("全局学习进阶事务", () => {
  let database: DatabaseResource,
    engine: LearningEngineRepository,
    service: LearningService,
    app: FastifyInstance,
    auth: AuthService;
  const users: string[] = [],
    units: LearningUnit[] = [],
    courses: PromotionCourse[] = [];
  const roles = [`test.${randomUUID()}`, `test.${randomUUID()}`];
  const ownerRole = roles[0] ?? "test.role";
  let course: PromotionCourse;
  const config = integrationConfig();
  beforeAll(async () => {
    database = createDatabase(config);
    await runMigrations(database);
    const profile = createDomainLearningContext(database);
    const context = {
      profile: profile.difficulty,
      promotionProfile: profile.promotionProfile,
      promoteProfile: profile.promoteProfile,
      character: () => Promise.resolve(ownerRole),
    };
    engine = new LearningEngineRepository(database, context);
    service = createLearningService(database, context, undefined, undefined, courses);
    auth = await createAuthService(config, database);
    app = await buildApp(config, { logger: false });
    registerLearningRoutes(app, auth, service);
    // 九十个隔离工程单元用于走满实际计分链路，不是正式课程内容。
    for (let i = 0; i < 90; i++)
      units.push({
        ...learningFixture(`test.${randomUUID()}`),
        roleKey: roles[i % 2] ?? ownerRole,
      });
    for (let i = 0; i < 6; i++)
      units.push({
        ...learningFixture(`test.${randomUUID()}`),
        roleKey: roles[i % 2] ?? ownerRole,
        level: "primary4",
      });
    await engine.publishBatch(units);
    const transfer = units[0];
    if (!transfer) throw new Error("缺少迁移夹具。");
    course = {
      level: "primary3",
      version: 1,
      requiredGoals: [
        {
          id: "test.greetings",
          title: "工程测试主题",
          minimumCorrect: 12,
          minimumUnits: 2,
        },
      ],
      transferUnits: [
        { id: transfer.id, version: 1, contentHash: contentHash(transfer) },
      ],
      nextLevelRoles: roles,
      minimumNextUnitsPerRole: 3,
      story: {
        id: "test.promotion",
        title: "仅供程序验证的进阶短章",
        beats: [
          {
            id: "opening",
            speaker: "旁白",
            text: "A new page.",
            translation: "仅供工程验证。",
          },
          {
            id: "ending",
            speaker: "旁白",
            text: "Ready?",
            translation: "仅供工程验证。",
          },
        ],
      },
      review: {
        reviewer: "工程夹具",
        reviewedAt: "2026-09-26",
        notes:
          "这个课程仅供隔离事务与协议测试，不能发布或宣称完成了任何真实学年的教学。",
        sourceIds: ["test.source"],
      },
    };
    courses.push(course);
  });
  afterAll(async () => {
    await app.close();
    for (const user of users)
      await database.sql`delete from app.users where id=${user}`;
    for (const unit of units) {
      await database.sql`delete from app.learning_unit_versions where unit_id=${unit.id}`;
      await database.sql`delete from app.learning_units where id=${unit.id}`;
    }
    await database.close();
  });
  async function account() {
    const id = randomUUID();
    users.push(id);
    await database.sql`insert into app.users(id) values(${id})`;
    await database.sql`insert into app.user_profiles(user_id,difficulty) values(${id},'primary3')`;
    const tokens = await auth.loginFederated(
      id,
      0,
      { deviceId: randomUUID(), platform: "ios" },
      {},
    );
    const headers = { authorization: `Bearer ${tokens.accessToken}` };
    const characters = [randomUUID(), randomUUID()];
    for (let i = 0; i < 2; i++)
      await engine.inspect(id, (s) =>
        s.ensureCharacter(characters[i] ?? "", roles[i] ?? ownerRole),
      );
    const post = (path: string, payload: Record<string, unknown>) =>
      app.inject({
        method: "POST",
        url: "/v1/learning/promotions" + path,
        headers,
        payload,
      });
    return { id, headers, characters, post };
  }
  async function earnAll(user: Awaited<ReturnType<typeof account>>) {
    for (let i = 0; i < 90; i++)
      await engine.command(user.id, randomUUID(), "fixture.unit", { i }, async (s) => {
        const character = user.characters[i % 2] ?? "",
          state = await s.character(character);
        await s.recordMessage({
          characterId: character,
          cycleId: state.cycleId,
          messageId: randomUUID(),
          text: "x".repeat(1000),
        });
        const { attempt } = await s.start(character, "primary3");
        if (!attempt) throw new Error("测试题库提前耗尽。");
        const unit = units.find((u) => u.id === attempt.unit.id);
        if (!unit) throw new Error("找不到冻结单元。");
        for (const q of unit.questions)
          await s.submit({
            attemptId: attempt.id,
            roundId: attempt.round.id,
            questionId: q.id,
            answer: gradeAnswer(q, { kind: "skip" }).solution,
          });
        return s.finish(attempt.id, false);
      });
  }
  async function begin(user: Awaited<ReturnType<typeof account>>) {
    const r = await user.post("", { requestId: randomUUID(), level: "primary3" });
    expect(r.statusCode, r.body).toBe(200);
    return r.json<Promotion>();
  }
  async function advance(user: Awaited<ReturnType<typeof account>>, p: Promotion) {
    return service.advancePromotion(user.id, randomUUID(), p.id, p.revision);
  }
  const completion = (p: Promotion) => ({
    requestId: randomUUID(),
    expectedRevision: p.revision,
    expectedProfileVersion: p.profileVersion,
    confirmed: true,
  });

  it("身份隔离、课程未发布与未达标条件明确，不因自选难度而获得资格", async () => {
    const user = await account();
    expect(
      (await app.inject({ url: "/v1/learning/promotions/" + randomUUID() })).statusCode,
    ).toBe(401);
    const denied = await user.post("", { requestId: randomUUID(), level: "primary3" });
    expect(denied.statusCode).toBe(409);
    expect(
      (await service.journey(user.id)).promotion.blockers.map((b) => b.code),
    ).toEqual(["points_remaining", "goals_remaining", "transfer_remaining"]);
    await database.sql`update app.user_profiles set difficulty='senior2' where user_id=${user.id}`;
    const unavailable = (await service.journey(user.id)).promotion;
    expect(unavailable.ready).toBe(false);
    expect(unavailable.courseVersion).toBeNull();
    expect(unavailable.blockers.map((b) => b.code)).toContain("course_unpublished");
    expect(
      (await user.post("", { requestId: randomUUID(), level: "primary3" })).statusCode,
    ).toBe(409);
  });
  it("跨角色通过实际判题积累540点，剧情恢复、幂等晋级与档案同步只发生一次", async () => {
    const user = await account();
    await earnAll(user);
    const eligibility = (await service.journey(user.id)).promotion;
    expect(eligibility).toMatchObject({
      points: 540,
      ready: true,
      transferCompleted: true,
      goals: [{ correct: 540, units: 90, complete: true }],
    });
    const ongoingCharacter = randomUUID();
    await engine.command(user.id, randomUUID(), "fixture.ongoing", {}, async (s) => {
      const state = await s.ensureCharacter(ongoingCharacter, ownerRole);
      await s.recordMessage({
        characterId: ongoingCharacter,
        cycleId: state.cycleId,
        messageId: randomUUID(),
        text: "x".repeat(1000),
      });
      return { recorded: true };
    });
    const ongoing = (await service.start(user.id, randomUUID(), ongoingCharacter))
      .attempt;
    if (!ongoing) throw new Error("缺少升级前未完成挑战。");
    const first = await begin(user),
      same = await begin(user);
    expect(same.id).toBe(first.id);
    expect(
      (await user.post("/" + first.id + "/complete", completion(first))).statusCode,
    ).toBe(409);
    let p = await advance(user, first);
    expect((await service.promotion(user.id, p.id)).acknowledgedBeats).toBe(1);
    const outsider = await account();
    expect(
      (
        await app.inject({
          url: "/v1/learning/promotions/" + p.id,
          headers: outsider.headers,
        })
      ).statusCode,
    ).toBe(404);
    const requestId = randomUUID();
    const a = await service.advancePromotion(user.id, requestId, p.id, p.revision);
    expect(
      await service.advancePromotion(user.id, requestId, p.id, p.revision),
    ).toEqual(a);
    p = a;
    expect(p.acknowledgedBeats).toBe(2);
    expect(
      (
        await user.post("/" + p.id + "/complete", {
          ...completion(p),
          confirmed: false,
        })
      ).statusCode,
    ).toBe(400);
    const payload = completion(p),
      responses = await Promise.all([
        user.post("/" + p.id + "/complete", payload),
        user.post("/" + p.id + "/complete", { ...payload, requestId: randomUUID() }),
      ]);
    expect(responses.map((r) => r.statusCode)).toEqual([200, 200]);
    const completed = responses[0].json<Promotion>();
    expect(completed).toMatchObject({
      status: "completed",
      completedProfileVersion: 2,
    });
    const exported = await createAccountService(config, database).exportData(user.id);
    expect(
      exported.learningRecords.find(
        (record) =>
          typeof record === "object" &&
          record !== null &&
          "recordType" in record &&
          record.recordType === "promotion",
      ),
    ).toMatchObject({
      recordType: "promotion",
      payload: { id: p.id, status: "completed" },
    });
    expect((await service.journey(user.id)).currentLevel).toBe("primary4");
    expect(
      await database.sql`select id from app.learning_promotions where user_id=${user.id} and status='completed'`,
    ).toHaveLength(1);
    expect(
      await database.sql`select event_id from app.sync_changes where user_id=${user.id} and event_type='profile.update' and payload->>'difficulty'='primary4'`,
    ).toHaveLength(1);
    expect(
      (await engine.read(user.id, (s) => s.progress())).find(
        (p) => p.level === "primary3",
      )?.points,
    ).toBe(540);
    expect(
      (await engine.read(user.id, (s) => s.progress())).find(
        (p) => p.level === "primary4",
      ),
    ).toBeUndefined();
    expect((await service.attempt(user.id, ongoing.id)).unit.level).toBe("primary3");
    await engine.command(user.id, randomUUID(), "fixture.finish-old", {}, async (s) => {
      const unit = units.find((u) => u.id === ongoing.unit.id);
      if (!unit) throw new Error("缺少冻结旧题。");
      for (const q of unit.questions)
        await s.submit({
          attemptId: ongoing.id,
          roundId: ongoing.round.id,
          questionId: q.id,
          answer: gradeAnswer(q, { kind: "skip" }).solution,
        });
      await s.finish(ongoing.id, false);
      const state = await s.character(ongoingCharacter);
      await s.recordMessage({
        characterId: ongoingCharacter,
        cycleId: state.cycleId,
        messageId: randomUUID(),
        text: "x".repeat(1000),
      });
      return { recorded: true };
    });
    expect(
      (await service.start(user.id, randomUUID(), ongoingCharacter)).attempt?.unit
        .level,
    ).toBe("primary4");
    const progress = await engine.read(user.id, (s) => s.progress());
    expect(progress.find((p) => p.level === "primary3")?.points).toBe(546);
    expect(progress.find((p) => p.level === "primary4")?.points ?? 0).toBe(0);
    const oldEvidence = await engine.read(user.id, (s) =>
      s.promotions(courses).eligibility("primary3"),
    );
    expect(oldEvidence.goals[0]).toMatchObject({ correct: 540, units: 90 });
    const domain = createDomainService(database, createLearningMilestoneReader());
    await domain.updateProfile(user.id, randomUUID(), {
      difficulty: "senior2",
      expectedVersion: 2,
    });
    expect((await user.post("/" + p.id + "/complete", completion(p))).statusCode).toBe(
      200,
    );
    expect((await service.journey(user.id)).currentLevel).toBe("senior2");
  }, 30000);
  it("课程变化、内容撤下、档案并发切换和事务故障均不能产生半次升级", async () => {
    const user = await account();
    await earnAll(user);
    // 总分达标不能替代主题覆盖与已审核迁移题版本。
    courses[0] = {
      ...course,
      requiredGoals: [
        { id: "test.missing", title: "缺少的主题", minimumCorrect: 2, minimumUnits: 2 },
      ],
      transferUnits: course.transferUnits.map((unit) => ({
        ...unit,
        contentHash: "0".repeat(64),
      })),
    };
    expect(
      (await service.journey(user.id)).promotion.blockers.map((b) => b.code),
    ).toEqual(["goals_remaining", "transfer_remaining"]);
    expect(
      (await user.post("", { requestId: randomUUID(), level: "primary3" })).statusCode,
    ).toBe(409);
    courses[0] = course;
    let p = await begin(user);
    p = await advance(user, p);
    p = await advance(user, p);
    const next = units.find((u) => u.level === "primary4");
    if (!next) throw new Error("缺少下一档夹具。");
    await database.sql`update app.learning_units set published=false where id=${next.id}`;
    expect((await user.post("/" + p.id + "/complete", completion(p))).statusCode).toBe(
      409,
    );
    expect(
      (await service.journey(user.id)).promotion.blockers.map((b) => b.code),
    ).toContain("next_level_unavailable");
    await database.sql`update app.learning_units set published=true where id=${next.id}`;
    courses[0] = { ...course, version: 2 };
    expect((await user.post("/" + p.id + "/complete", completion(p))).statusCode).toBe(
      409,
    );
    const newer = await begin(user);
    expect(newer.id).not.toBe(p.id);
    expect((await service.promotion(user.id, p.id)).status).toBe("superseded");
    p = await advance(user, newer);
    p = await advance(user, p);
    const profile = createDomainLearningContext(database);
    const broken = createLearningService(
      database,
      {
        profile: profile.difficulty,
        character: () => Promise.resolve(ownerRole),
        promotionProfile: profile.promotionProfile,
        promoteProfile: async (...args) => {
          await profile.promoteProfile(...args);
          throw new Error("隔离故障：在档案写入后回滚。");
        },
      },
      undefined,
      undefined,
      courses,
    );
    await expect(
      broken.completePromotion(
        user.id,
        randomUUID(),
        p.id,
        p.revision,
        p.profileVersion,
      ),
    ).rejects.toThrow("隔离故障");
    expect((await service.journey(user.id)).currentLevel).toBe("primary3");
    expect((await service.promotion(user.id, p.id)).status).toBe("started");
    expect(
      await database.sql`select event_id from app.sync_changes where user_id=${user.id}`,
    ).toHaveLength(0);
    const domain = createDomainService(database, createLearningMilestoneReader());
    const results = await Promise.allSettled([
      service.completePromotion(
        user.id,
        randomUUID(),
        p.id,
        p.revision,
        p.profileVersion,
      ),
      domain.updateProfile(user.id, randomUUID(), {
        difficulty: "senior2",
        expectedVersion: p.profileVersion,
      }),
    ]);
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    const current = (await service.journey(user.id)).currentLevel;
    expect(["primary4", "senior2"]).toContain(current);
    const record = await service.promotion(user.id, p.id);
    expect(record.status).toBe(current === "primary4" ? "completed" : "started");
    courses[0] = course;
  }, 30000);
});
