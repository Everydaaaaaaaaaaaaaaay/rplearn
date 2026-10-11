import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { learningDirectionKeys } from "../../src/modules/learning/direction.js";
import { createLearningService } from "../../src/modules/learning/service.js";
import { integrationConfig } from "../helpers/integration.js";
import { learningFixture } from "../helpers/learning.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")("并列备考方向", () => {
  let database: DatabaseResource;
  let repository: LearningEngineRepository;
  const users: string[] = [];
  const units: string[] = [];
  beforeAll(async () => {
    database = createDatabase(integrationConfig());
    await runMigrations(database);
    repository = new LearningEngineRepository(database);
  });
  afterAll(async () => {
    for (const user of users)
      await database.sql`delete from app.users where id=${user}`;
    for (const unit of units) {
      await database.sql`delete from app.learning_unit_versions where unit_id=${unit}`;
      await database.sql`delete from app.learning_units where id=${unit}`;
    }
    await database.close();
  });

  async function setup() {
    const user = randomUUID();
    const character = randomUUID();
    const role = `test.${randomUUID()}`;
    users.push(user);
    await database.sql`insert into app.users(id) values(${user})`;
    const unit = { ...learningFixture(`test.${randomUUID()}`), roleKey: role };
    units.push(unit.id);
    await repository.publish(unit);
    const service = createLearningService(database, {
      profile: () => Promise.resolve("primary3"),
      character: () => Promise.resolve(role),
    });
    const state = await service.character(user, character);
    await service.debugFill(user, randomUUID(), character, state.cycleId);
    return { user, character, role, service };
  }

  it("默认通用英语，方向切换不修改年级、积分或挑战字数，四个考试方向互不替代", async () => {
    const c = await setup();
    const initial = await c.service.directions(c.user);
    expect(initial.selectedDirection).toBe("general");
    expect(initial.revision).toBe(0);
    expect(initial.directions.map((item) => item.id)).toEqual(learningDirectionKeys);
    const before = await c.service.journey(c.user);
    const characterBefore = await c.service.character(c.user, c.character);
    let revision = 0;
    for (const direction of learningDirectionKeys.slice(1)) {
      const selected = await c.service.selectDirection(
        c.user,
        randomUUID(),
        direction,
        revision,
      );
      expect(selected).toMatchObject({
        selectedDirection: direction,
        revision: ++revision,
      });
      const character = await c.service.character(c.user, c.character);
      expect(character).toMatchObject({
        level: "primary3",
        characters: 1000,
        cycleId: characterBefore.cycleId,
        availableUnits: 0,
        generationStatus: null,
      });
      expect(await c.service.journey(c.user)).toMatchObject({
        currentLevel: before.currentLevel,
        levels: before.levels,
        promotion: before.promotion,
      });
      await expect(
        c.service.start(c.user, randomUUID(), c.character),
      ).rejects.toMatchObject({ code: "LEARNING_DIRECTION_NOT_READY" });
    }
    const [row] =
      await database.sql`select count(*)::int as count from app.learning_attempts where user_id=${c.user}`;
    expect(row?.count).toBe(0);
    expect((await c.service.character(c.user, c.character)).characters).toBe(1000);
    await c.service.selectDirection(c.user, randomUUID(), "general", revision);
    expect((await c.service.start(c.user, randomUUID(), c.character)).status).toBe(
      "started",
    );
  });

  it("跨设备版本冲突和幂等重放不会覆盖新选择，账号互相隔离", async () => {
    const c = await setup();
    const other = await setup();
    const requestId = randomUUID();
    const first = await c.service.selectDirection(
      c.user,
      requestId,
      "entrance-english-1",
      0,
    );
    expect(
      await c.service.selectDirection(c.user, requestId, "entrance-english-1", 0),
    ).toEqual(first);
    const races = await Promise.allSettled([
      c.service.selectDirection(c.user, randomUUID(), "toefl-ibt-2026", 1),
      c.service.selectDirection(c.user, randomUUID(), "ielts-academic", 1),
    ]);
    expect(races.filter((result) => result.status === "fulfilled")).toHaveLength(1);
    expect(races.find((result) => result.status === "rejected")).toMatchObject({
      reason: { code: "LEARNING_DIRECTION_CONFLICT" },
    });
    const current = await c.service.directions(c.user);
    expect(current.revision).toBe(2);
    expect(
      await c.service.selectDirection(c.user, requestId, "entrance-english-1", 0),
    ).toEqual(first);
    expect(await c.service.directions(c.user)).toEqual(current);
    await expect(
      c.service.selectDirection(c.user, requestId, "entrance-english-2", 0),
    ).rejects.toMatchObject({ code: "LEARNING_REQUEST_CONFLICT" });
    expect((await other.service.directions(other.user)).selectedDirection).toBe(
      "general",
    );
    expect(
      await c.service.selectDirection(
        c.user,
        randomUUID(),
        current.selectedDirection,
        2,
      ),
    ).toEqual(current);
  });

  it("切换后继续旧挑战与补答沿用原来的通用英语归属，不消耗下一轮进度", async () => {
    const c = await setup();
    const started = await c.service.start(c.user, randomUUID(), c.character);
    if (!started.attempt) throw new Error("测试挑战没有开启。");
    let attempt = started.attempt;
    expect(attempt.direction).toBe("general");
    await c.service.selectDirection(c.user, randomUUID(), "ielts-academic", 0);
    expect((await c.service.start(c.user, randomUUID(), c.character)).attempt).toEqual(
      attempt,
    );
    attempt = await c.service.finish(c.user, randomUUID(), {
      attemptId: attempt.id,
      expectedRevision: attempt.revision,
      skipRemaining: true,
    });
    attempt = await c.service.retry(c.user, randomUUID(), {
      attemptId: attempt.id,
      expectedRevision: attempt.revision,
    });
    const input = {
      attemptId: attempt.id,
      roundId: attempt.round.id,
      questionId: "q.choice",
      expectedRevision: attempt.revision,
      answer: { kind: "choice" as const, optionId: "hello" },
    };
    const requestId = randomUUID();
    const result = await c.service.answer(c.user, requestId, input);
    expect(result.awardedPoints).toBe(1);
    expect(result.attempt.direction).toBe("general");
    expect(result.progress).toMatchObject([{ level: "primary3", points: 1 }]);
    expect(await c.service.answer(c.user, requestId, input)).toEqual(result);
    expect((await c.service.history(c.user, c.character, 20)).items[0]).toMatchObject({
      id: attempt.id,
      direction: "general",
      level: "primary3",
      correctCount: 1,
    });
    expect((await c.service.character(c.user, c.character)).characters).toBe(0);
    expect((await c.service.directions(c.user)).selectedDirection).toBe(
      "ielts-academic",
    );
  });
});
