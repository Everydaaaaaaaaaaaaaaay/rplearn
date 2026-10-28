import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { buildApp } from "../../src/app.js";
import { createAuthService, type AuthService } from "../../src/modules/auth/service.js";
import {
  createDomainLearningContext,
  createDomainService,
} from "../../src/modules/domain/service.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import {
  createLearningService,
  type LearningService,
} from "../../src/modules/learning/service.js";
import {
  contentHash,
  type LearningLevel,
  type LearningUnit,
} from "../../src/modules/learning/content.js";
import { gradeAnswer } from "../../src/modules/learning/grading.js";
import { type PromotionCourse } from "../../src/modules/learning/promotion-content.js";
import { registerLearningRoutes } from "../../src/modules/learning/routes.js";
import { integrationConfig } from "../helpers/integration.js";
import { freshLearningFixture } from "../helpers/learning.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")("九星自动进阶事务", () => {
  let database: DatabaseResource,
    engine: LearningEngineRepository,
    service: LearningService,
    auth: AuthService,
    app: FastifyInstance;
  const users: string[] = [],
    units: LearningUnit[] = [];
  const role = `test.${randomUUID()}`;
  const config = integrationConfig();
  const context = () => {
    const profile = createDomainLearningContext(database);
    return {
      profile: profile.difficulty,
      promotionProfile: profile.promotionProfile,
      promoteProfile: profile.promoteProfile,
      character: () => Promise.resolve(role),
    };
  };
  beforeAll(async () => {
    database = createDatabase(config);
    await runMigrations(database);
    engine = new LearningEngineRepository(database, context());
    service = createLearningService(database, context());
    app = await buildApp(config, { logger: false });
    auth = await createAuthService(config, database);
    registerLearningRoutes(app, auth, service);
    for (const level of ["primary3", "primary4"] as const)
      units.push({
        ...freshLearningFixture(`test.${randomUUID()}`),
        roleKey: role,
        level,
      });
    await engine.publishBatch(units);
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
  async function account(points = 539, level: LearningLevel = "primary3") {
    const id = randomUUID(),
      character = randomUUID();
    users.push(id);
    await database.sql`insert into app.users(id) values(${id})`;
    await database.sql`insert into app.user_profiles(user_id,difficulty) values(${id},${level})`;
    // Existing earned balances are authoritative and must survive this policy change.
    await database.sql`insert into app.learning_level_progress(user_id,level_key,points) values(${id},${level},${points})`;
    return { id, character };
  }
  async function start(user: Awaited<ReturnType<typeof account>>) {
    await engine.command(user.id, randomUUID(), "fixture.ready", {}, async (s) => {
      const state = await s.ensureCharacter(user.character, role);
      await s.recordMessage({
        characterId: user.character,
        cycleId: state.cycleId,
        messageId: randomUUID(),
        text: "x".repeat(1000),
      });
      return { ready: true };
    });
    const result = await service.start(user.id, randomUUID(), user.character);
    if (!result.attempt) throw new Error("Missing frozen test practice");
    return result.attempt;
  }
  async function answer(
    userId: string,
    attempt: Awaited<ReturnType<typeof start>>,
    index = 0,
    requestId = randomUUID(),
  ) {
    const unit = units.find((u) => u.id === attempt.unit.id),
      question = unit?.questions[index];
    if (!question) throw new Error("Missing test question");
    return service.answer(userId, requestId, {
      attemptId: attempt.id,
      roundId: attempt.round.id,
      questionId: question.id,
      expectedRevision: attempt.revision,
      answer: gradeAnswer(question, { kind: "skip" }).solution,
    });
  }
  async function profile(userId: string) {
    const [row] = await database.sql<
      { difficulty: LearningLevel; version: number }[]
    >`select difficulty,version from app.user_profiles where user_id=${userId}`;
    return row;
  }
  async function updates(userId: string) {
    return database.sql<
      { command_id: string; payload: unknown }[]
    >`select command_id,payload from app.sync_changes where user_id=${userId} and event_type='profile.update'`;
  }

  it("539点保留原等级，资格不再要求课程、专项题或下一档供给", async () => {
    const user = await account();
    const journey = await service.journey(user.id);
    expect(journey.currentLevel).toBe("primary3");
    expect(journey.promotion.blockers.map((b) => b.code)).toEqual(["points_remaining"]);
    expect(await profile(user.id)).toMatchObject({
      difficulty: "primary3",
      version: 1,
    });
    expect(await updates(user.id)).toHaveLength(0);
  });

  it("第540个已获点立即进阶，重复和并发收据只写一次档案与同步事件", async () => {
    const user = await account(),
      attempt = await start(user),
      requestId = randomUUID();
    const [first, replay] = await Promise.all([
      answer(user.id, attempt, 0, requestId),
      answer(user.id, attempt, 0, requestId),
    ]);
    expect(first).toEqual(replay);
    expect(first).toMatchObject({
      awardedPoints: 1,
      currentLevel: "primary4",
      automaticPromotion: {
        fromLevel: "primary3",
        toLevel: "primary4",
        profileVersion: 2,
      },
    });
    expect(await profile(user.id)).toMatchObject({
      difficulty: "primary4",
      version: 2,
    });
    expect(await updates(user.id)).toHaveLength(1);
    expect(await engine.read(user.id, (s) => s.progress())).toMatchObject([
      { level: "primary3", points: 540 },
    ]);
    expect((await service.journey(user.id)).currentLevel).toBe("primary4");
  });

  it("已满档案在打开旅程时补进阶，只有已经各自满540的等级才可连续前进", async () => {
    const user = await account(547);
    await database.sql`insert into app.learning_level_progress(user_id,level_key,points) values(${user.id},'primary4',540),(${user.id},'primary5',539)`;
    const [a, b] = await Promise.all([
      service.journey(user.id),
      service.journey(user.id),
    ]);
    expect([a.currentLevel, b.currentLevel]).toEqual(["primary5", "primary5"]);
    expect(await profile(user.id)).toMatchObject({
      difficulty: "primary5",
      version: 3,
    });
    const changes = await updates(user.id);
    expect(changes).toHaveLength(2);
    expect(new Set(changes.map((r) => r.command_id)).size).toBe(2);
    expect(
      (await engine.read(user.id, (s) => s.progress())).map((p) => [p.level, p.points]),
    ).toEqual([
      ["primary3", 547],
      ["primary4", 540],
      ["primary5", 539],
    ]);
  });

  it("开始新挑战也补进阶，显式只读仓库从不修改已满档案", async () => {
    const user = await account(540);
    await engine.read(user.id, (s) => s.progress());
    await engine.read(user.id, (s) => s.promotions([]).eligibility("primary3"));
    expect(await profile(user.id)).toMatchObject({
      difficulty: "primary3",
      version: 1,
    });
    expect((await start(user)).unit.level).toBe("primary4");
    expect(await updates(user.id)).toHaveLength(1);
  });

  it("晋级后未完旧挑战继续判题，答案与新增积分都留在冻结原等级", async () => {
    const user = await account(),
      attempt = await start(user);
    const first = await answer(user.id, attempt);
    expect((await service.attempt(user.id, attempt.id)).unit.level).toBe("primary3");
    const second = await answer(user.id, first.attempt, 1);
    expect(second).toMatchObject({
      awardedPoints: 1,
      currentLevel: "primary4",
      automaticPromotion: null,
    });
    expect(second.attempt.unit.level).toBe("primary3");
    expect(second.progress.find((p) => p.level === "primary3")?.points).toBe(541);
    expect(second.progress.find((p) => p.level === "primary4")).toBeUndefined();
    expect(
      await database.sql`select question_id from app.learning_answers where round_id=${attempt.round.id}`,
    ).toHaveLength(2);
    expect(await updates(user.id)).toHaveLength(1);
  });

  it("最高等级九星后保留余额并继续练习，不反复改档", async () => {
    const user = await account(550, "advanced");
    const journey = await service.journey(user.id);
    expect(journey.currentLevel).toBe("advanced");
    expect(journey.promotion.blockers.map((b) => b.code)).toEqual(["highest_level"]);
    expect(await profile(user.id)).toMatchObject({
      difficulty: "advanced",
      version: 1,
    });
    expect(await updates(user.id)).toHaveLength(0);
  });

  it("并发答题与自选水平使用同一档案版本边界，冻结旧题仍只奖励一次", async () => {
    const user = await account(),
      attempt = await start(user);
    const results = await Promise.allSettled([
      answer(user.id, attempt),
      createDomainService(database).updateProfile(user.id, randomUUID(), {
        difficulty: "primary5",
        expectedVersion: 1,
      }),
    ]);
    expect(results[0].status).toBe("fulfilled");
    const current = await profile(user.id);
    expect(["primary4", "primary5"]).toContain(current?.difficulty);
    expect(current?.version).toBe(2);
    expect(await updates(user.id)).toHaveLength(1);
    expect((await engine.read(user.id, (s) => s.progress()))[0]?.points).toBe(540);
  });

  it("旅程权限保持原有登录边界，匿名账号不会绕过领域晋级限制", async () => {
    const user = await account(540);
    await database.sql`insert into app.guest_installations(user_id,installation_hash) values(${user.id},${randomUUID().replaceAll("-", "").repeat(2)})`;
    const tokens = await auth.loginFederated(
      user.id,
      0,
      { deviceId: randomUUID(), platform: "ios" },
      {},
    );
    const response = await app.inject({
      url: "/v1/learning/journey",
      headers: { authorization: `Bearer ${tokens.accessToken}` },
    });
    expect(response.statusCode).toBe(403);
    expect(response.json<{ code: string }>().code).toBe("LOGIN_REQUIRED");
    expect(await profile(user.id)).toMatchObject({
      difficulty: "primary3",
      version: 1,
    });
    expect(await updates(user.id)).toHaveLength(0);
  });

  it("档案写入后故障回滚答案、奖励、余额和同步，原请求可安全重试", async () => {
    const user = await account(),
      attempt = await start(user),
      requestId = randomUUID();
    const profileContext = context();
    const broken = createLearningService(database, {
      ...profileContext,
      promoteProfile: async (...args) => {
        await profileContext.promoteProfile(...args);
        throw new Error("isolated promotion rollback");
      },
    });
    const question = units[0]?.questions[0];
    if (!question) throw new Error("Missing question");
    await expect(
      broken.answer(user.id, requestId, {
        attemptId: attempt.id,
        roundId: attempt.round.id,
        questionId: question.id,
        expectedRevision: attempt.revision,
        answer: gradeAnswer(question, { kind: "skip" }).solution,
      }),
    ).rejects.toThrow("isolated promotion rollback");
    expect(await profile(user.id)).toMatchObject({
      difficulty: "primary3",
      version: 1,
    });
    expect(await updates(user.id)).toHaveLength(0);
    expect(
      await database.sql`select question_id from app.learning_answers where round_id=${attempt.round.id}`,
    ).toHaveLength(0);
    expect((await engine.read(user.id, (s) => s.progress()))[0]?.points).toBe(539);
    expect(await answer(user.id, attempt, 0, requestId)).toMatchObject({
      awardedPoints: 1,
      currentLevel: "primary4",
    });
  });

  it("历史手动进阶的冻结剧情仍可读取，自动晋级不改写旧快照", async () => {
    const user = await account(540),
      id = randomUUID();
    const unit = units[0];
    if (!unit) throw new Error("Missing legacy transfer unit");
    const course: PromotionCourse = {
      level: "primary3",
      version: 1,
      requiredGoals: [
        { id: "test.greetings", title: "旧主题", minimumCorrect: 1, minimumUnits: 2 },
      ],
      transferUnits: [{ id: unit.id, version: 1, contentHash: contentHash(unit) }],
      nextLevelRoles: [role],
      minimumNextUnitsPerRole: 3,
      story: {
        id: "test.legacy",
        title: "历史剧情",
        beats: [
          { id: "old", speaker: "旁白", text: "A new page.", translation: "旧记录。" },
          { id: "end", speaker: "旁白", text: "Ready?", translation: "完成旧记录。" },
        ],
      },
      review: {
        reviewer: "工程夹具",
        reviewedAt: "2026-09-26",
        notes: "仅供隔离程序验证的历史课程冻结快照，不用于正式教学内容或线上发布。",
        sourceIds: ["test.source"],
      },
    };
    await database.sql`insert into app.learning_promotions(id,user_id,from_level,to_level,course_hash,course,profile_version) values(${id},${user.id},'primary3','primary4',${contentHash(course)},${JSON.stringify(course)}::jsonb,1)`;
    const before = await service.promotion(user.id, id);
    await service.journey(user.id);
    expect(await service.promotion(user.id, id)).toEqual(before);
    expect(before.story.title).toBe("历史剧情");
  });
});
