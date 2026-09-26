import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  LearningEngineRepository,
  type LearningSession,
} from "../../src/modules/learning/engine-repository.js";
import { gradeAnswer } from "../../src/modules/learning/grading.js";
import { integrationConfig } from "../helpers/integration.js";
import { learningFixture } from "../helpers/learning.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")("单元学习事务引擎", () => {
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
    await database.sql`delete from app.learning_generation_jobs where role_key like 'test.%'`;
    await database.close();
  });

  async function setup(count = 2) {
    const user = randomUUID();
    const character = randomUUID();
    const role = `test.${randomUUID()}`;
    users.push(user);
    await database.sql`insert into app.users(id) values(${user})`;
    for (let i = 0; i < count; i++) {
      const unit = { ...learningFixture(`test.${randomUUID()}`), roleKey: role };
      units.push(unit.id);
      await repository.publish(unit);
    }
    const command = <T>(
      input: unknown,
      action: (session: LearningSession) => Promise<T>,
      requestId = randomUUID(),
    ) => repository.command(user, requestId, "test", input, action);
    const state = await command({ character }, (session) =>
      session.ensureCharacter(character, role),
    );
    const fill = async () => {
      const current = await repository.read(user, (session) =>
        session.character(character),
      );
      const input = {
        characterId: character,
        cycleId: current.cycleId,
        messageId: randomUUID(),
        text: "a".repeat(1000),
      };
      return command(input, (session) => session.recordMessage(input));
    };
    const start = async () => {
      const result = await command({ character, start: true }, (session) =>
        session.start(character, "primary3"),
      );
      if (!result.attempt) throw new Error("测试题库未分配单元。");
      return result.attempt;
    };
    return { user, character, role, command, state, fill, start };
  }

  it("角色独立、同消息去重、满条封顶、旧周期事件不能填新条", async () => {
    const c = await setup();
    const other = randomUUID();
    await c.command({ other }, (s) => s.ensureCharacter(other, c.role));
    const input = {
      characterId: c.character,
      cycleId: c.state.cycleId,
      messageId: randomUUID(),
      text: "中".repeat(600),
    };
    await Promise.all([
      c.command(input, (s) => s.recordMessage(input)),
      c.command(input, (s) => s.recordMessage(input)),
    ]);
    expect(
      (await repository.read(c.user, (s) => s.character(c.character))).characters,
    ).toBe(600);
    expect((await repository.read(c.user, (s) => s.character(other))).characters).toBe(
      0,
    );
    expect((await c.fill()).characters).toBe(1000);
    const attempt = await c.start();
    await c.command({ finish: attempt.id }, (s) => s.finish(attempt.id, true));
    const staleInput = { ...input, messageId: randomUUID() };
    await c.command(staleInput, (s) => s.recordMessage(staleInput));
    expect(
      (await repository.read(c.user, (s) => s.character(c.character))).characters,
    ).toBe(0);
  });

  it("并发开始只分配一个挑战，首轮不允许无意结束", async () => {
    const c = await setup();
    await expect(c.start()).rejects.toMatchObject({ code: "LEARNING_NOT_READY" });
    await c.fill();
    const [first, second] = await Promise.all([c.start(), c.start()]);
    expect(first.id).toBe(second.id);
    await expect(
      c.command({ finish: first.id }, (s) => s.finish(first.id, false)),
    ).rejects.toMatchObject({ code: "LEARNING_ROUND_INCOMPLETE" });
    expect(
      (await repository.read(c.user, (s) => s.character(c.character))).characters,
    ).toBe(1000);
  });

  it("部分得分、补答和旧档分数独立，重试不能重复领奖或重置新周期", async () => {
    const c = await setup();
    await c.fill();
    const attempt = await c.start();
    const questions = learningFixture().questions;
    for (const question of questions.slice(0, 4)) {
      const input = {
        attemptId: attempt.id,
        roundId: attempt.round.id,
        questionId: question.id,
        answer: gradeAnswer(question, { kind: "skip" }).solution,
      };
      const requestId = randomUUID();
      const [a, b] = await Promise.all([
        c.command(input, (s) => s.submit(input), requestId),
        c.command(input, (s) => s.submit(input), requestId),
      ]);
      expect(a).toEqual(b);
      expect(a.awardedPoints).toBe(1);
      await expect(c.command(input, (s) => s.submit(input))).rejects.toMatchObject({
        code: "LEARNING_ALREADY_ANSWERED",
      });
    }
    await c.command({ finish: attempt.id }, (s) => s.finish(attempt.id, true));
    expect((await repository.read(c.user, (s) => s.progress()))[0]).toMatchObject({
      level: "primary3",
      points: 4,
    });
    await c.fill();
    const next = await c.start();
    expect(next.unit.id).not.toBe(attempt.unit.id);
    const retry = await c.command({ retry: attempt.id }, (s) => s.retry(attempt.id));
    expect(retry.round.questionIds).toHaveLength(2);
    for (const question of questions.slice(4)) {
      const input = {
        attemptId: attempt.id,
        roundId: retry.round.id,
        questionId: question.id,
        answer: gradeAnswer(question, { kind: "skip" }).solution,
      };
      await c.command(input, (s) => s.submit(input));
    }
    const finished = await repository.read(c.user, (s) => s.attempt(attempt.id));
    expect(finished.correctQuestionIds).toHaveLength(6);
    expect(finished.round.completed).toBe(true);
    const state = await repository.read(c.user, (s) => s.character(c.character));
    expect(state.activeAttemptId).toBe(next.id);
    expect(state.characters).toBe(1000);
    await c.command({ retry: attempt.id }, (s) => s.retry(attempt.id));
    expect((await repository.read(c.user, (s) => s.progress()))[0]).toMatchObject({
      level: "primary3",
      points: 6,
    });
    await expect(
      c.command({ missingAttempt: true }, (s) => s.attempt(randomUUID())),
    ).rejects.toMatchObject({ statusCode: 404 });
  });

  it("内容版本冻结，耗尽后保留机会并只排一个共享生成任务", async () => {
    const c = await setup(1);
    await c.fill();
    const first = await c.start();
    const updated = {
      ...learningFixture(first.unit.id),
      roleKey: c.role,
      version: 2,
      title: "修订标题",
    };
    await repository.publish(updated);
    await expect(
      repository.publish({ ...updated, title: "偷偷改同版本" }),
    ).rejects.toMatchObject({ code: "LEARNING_IMMUTABLE_CONTENT" });
    expect(
      (await repository.read(c.user, (s) => s.attempt(first.id))).unit.version,
    ).toBe(1);
    await c.command({ finish: first.id }, (s) => s.finish(first.id, true));
    await c.fill();
    for (let i = 0; i < 2; i++) {
      expect(
        await c.command({ start: c.character }, (s) =>
          s.start(c.character, "primary3"),
        ),
      ).toEqual({ status: "preparing", attempt: null });
    }
    expect(
      (await repository.read(c.user, (s) => s.character(c.character))).characters,
    ).toBe(1000);
    const jobs =
      await database.sql`select id from app.learning_generation_jobs where role_key=${c.role}`;
    expect(jobs).toHaveLength(1);
  });

  it("多个角色共建同档星星，补答始终计入挑战原档且里程碑不重复", async () => {
    const c = await setup(10);
    const questions = learningFixture().questions;
    const answerRound = async (
      attempt: Awaited<ReturnType<typeof c.start>>,
      count: number,
    ) => {
      for (const question of questions.slice(0, count)) {
        const input = {
          attemptId: attempt.id,
          roundId: attempt.round.id,
          questionId: question.id,
          answer: gradeAnswer(question, { kind: "skip" }).solution,
        };
        await c.command(input, (s) => s.submit(input));
      }
    };
    for (let i = 0; i < 9; i++) {
      await c.fill();
      const attempt = await c.start();
      await answerRound(attempt, 6);
      await c.command({ finish: attempt.id }, (s) => s.finish(attempt.id, false));
    }
    const other = randomUUID();
    const state = await c.command({ other }, (s) => s.ensureCharacter(other, c.role));
    const message = {
      characterId: other,
      cycleId: state.cycleId,
      messageId: randomUUID(),
      text: "a".repeat(1000),
    };
    await c.command(message, (s) => s.recordMessage(message));
    const result = await c.command({ start: other }, (s) => s.start(other, "primary3"));
    if (!result.attempt) throw new Error("测试题库缺少单元。");
    await answerRound(result.attempt, 5);
    expect((await repository.read(c.user, (s) => s.progress()))[0]).toMatchObject({
      points: 59,
      stars: 0,
    });
    await c.command({ finish: result.attempt.id }, (s) =>
      s.finish(result.attempt.id, true),
    );
    const retry = await c.command({ retry: result.attempt.id }, (s) =>
      s.retry(result.attempt.id),
    );
    const question = questions[5];
    if (!question) throw new Error("测试题不存在。");
    const input = {
      attemptId: retry.id,
      roundId: retry.round.id,
      questionId: question.id,
      answer: gradeAnswer(question, { kind: "skip" }).solution,
    };
    const requestId = randomUUID();
    await c.command(input, (s) => s.submit(input), requestId);
    await c.command(input, (s) => s.submit(input), requestId);
    expect((await repository.read(c.user, (s) => s.progress()))[0]).toMatchObject({
      level: "primary3",
      points: 60,
      stars: 1,
    });
    const milestones =
      await database.sql`select star from app.learning_milestones where user_id=${c.user}`;
    expect(milestones).toEqual([{ star: 1 }]);
    const higherUnit = {
      ...learningFixture(`test.${randomUUID()}`),
      roleKey: c.role,
      level: "primary4" as const,
    };
    units.push(higherUnit.id);
    await repository.publish(higherUnit);
    await c.fill();
    const higher = await c.command({ start: c.character, level: "primary4" }, (s) =>
      s.start(c.character, "primary4"),
    );
    if (!higher.attempt) throw new Error("测试高一档单元不存在。");
    await answerRound(higher.attempt, 1);
    expect(await repository.read(c.user, (s) => s.progress())).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ level: "primary3", points: 60, stars: 1 }),
        expect.objectContaining({ level: "primary4", points: 1, stars: 0 }),
      ]),
    );
  });

  it("隔离账号并原子回滚失败操作，同幂等键不能换请求", async () => {
    const c = await setup();
    await c.fill();
    const first = await c.start();
    const second = await setup();
    await expect(
      repository.read(second.user, (s) => s.attempt(first.id)),
    ).rejects.toMatchObject({ statusCode: 404 });
    const requestId = randomUUID();
    await c.command({ value: 1 }, (s) => s.character(c.character), requestId);
    await expect(
      c.command({ value: 2 }, (s) => s.character(c.character), requestId),
    ).rejects.toMatchObject({ code: "LEARNING_REQUEST_CONFLICT" });
    const q = learningFixture().questions[0];
    if (!q) throw new Error("测试题不存在。");
    const input = {
      attemptId: first.id,
      roundId: first.round.id,
      questionId: q.id,
      answer: gradeAnswer(q, { kind: "skip" }).solution,
    };
    await expect(
      c.command(input, async (s) => {
        await s.submit(input);
        throw new Error("模拟事务中断");
      }),
    ).rejects.toThrow("模拟事务中断");
    expect(await repository.read(c.user, (s) => s.progress())).toEqual([]);
    expect(
      (await repository.read(c.user, (s) => s.attempt(first.id))).round.answers,
    ).toEqual([]);
    const races = await Promise.allSettled([
      c.command(input, (s) => s.submit(input)),
      c.command(input, (s) => s.submit(input)),
    ]);
    expect(races.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect((await repository.read(c.user, (s) => s.progress()))[0]?.points).toBe(1);
  });
});
