import { randomUUID } from "node:crypto";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { integrationConfig } from "../helpers/integration.js";
import { generationFixture } from "../helpers/learning-generation.js";
import { LearningGenerationRepository } from "../../src/modules/learning/generation-repository.js";
import { createLearningGenerationProcessor } from "../../src/modules/learning/generation-processor.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { contentHash } from "../../src/modules/learning/content.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")("公共学习补库事务", () => {
  let database: DatabaseResource;
  let repository: LearningGenerationRepository;
  const jobIds: string[] = [],
    users: string[] = [],
    unitIds: string[] = [];
  beforeAll(async () => {
    database = createDatabase(integrationConfig());
    await runMigrations(database);
    repository = new LearningGenerationRepository(database);
  });
  afterAll(async () => {
    for (const id of users) await database.sql`delete from app.users where id=${id}`;
    for (const id of jobIds) {
      await database.sql`delete from app.learning_generation_runs where job_id=${id}`;
      await database.sql`delete from app.learning_generation_jobs where id=${id}`;
    }
    for (const id of unitIds) {
      await database.sql`delete from app.learning_unit_versions where unit_id=${id}`;
      await database.sql`delete from app.learning_units where id=${id}`;
    }
    await database.close();
  });
  const enqueue = async (id: string, role: string) => {
    jobIds.push(id);
    await database.sql`insert into app.learning_generation_jobs(id,role_key,level_key) values(${id},${role},'primary3')`;
  };
  it("两 Worker 只取一次；独立解题后仍不可抽取，逐题发布后两个账号复用", async () => {
    const id = randomUUID(),
      fixture = await generationFixture(id),
      role = `test.${id}`;
    fixture.blueprint = { ...fixture.blueprint, roleKey: role };
    fixture.unit.roleKey = role;
    const engine = new LearningEngineRepository(database);
    const characters = [randomUUID(), randomUUID()];
    for (const character of characters) {
      const user = randomUUID();
      users.push(user);
      await database.sql`insert into app.users(id) values(${user})`;
      await database.sql`insert into app.learning_characters(user_id,character_id,role_key,cycle_id,characters) values(${user},${character},${role},${randomUUID()},1000)`;
    }
    await enqueue(id, role);
    const complete = vi.fn(
      (input: {
        phase: "author" | "review";
        messages: readonly { content: string }[];
      }) => {
        if (input.phase === "review") {
          const data = JSON.parse(input.messages[1]?.content ?? "{}") as {
            questions: Record<string, unknown>[];
          };
          expect(
            data.questions.every(
              (q) =>
                !("answer" in q) && !("explanation" in q) && !("acceptedAnswers" in q),
            ),
          ).toBe(true);
        }
        return Promise.resolve({
          content:
            input.phase === "author" ? fixture.draft : JSON.stringify(fixture.report),
          model: "工程夹具",
          usage: { inputTokens: 100, outputTokens: 100 },
        });
      },
    );
    const processor = createLearningGenerationProcessor(
      repository,
      [fixture.blueprint],
      complete,
      50,
    );
    expect(
      (await Promise.all([processor.runOnce(), processor.runOnce()])).sort(),
    ).toEqual(["idle", "review"]);
    expect(complete).toHaveBeenCalledTimes(2);
    const job = await repository.inspect(id);
    expect(job.status).toBe("review");
    const user0 = users[0],
      user1 = users[1],
      char0 = characters[0],
      char1 = characters[1];
    if (!user0 || !user1 || !char0 || !char1) throw new Error("缺少测试账号。");
    expect(await engine.inspect(user0, (s) => s.start(char0, "primary3"))).toEqual({
      status: "preparing",
      attempt: null,
    });
    expect((await engine.read(user0, (s) => s.character(char0))).characters).toBe(1000);
    await expect(
      repository.publish(
        id,
        "0".repeat(64),
        fixture.blueprint,
        "测试审核者",
        "工程测试：逐题答案、题干独立性、反例、提示、解析和档位已按夹具核对。不可用于正式题库。",
      ),
    ).rejects.toThrow();
    await repository.publish(
      id,
      String(job.candidate_hash),
      fixture.blueprint,
      "测试审核者",
      "工程测试：逐题答案、题干独立性、反例、提示、解析和档位已按夹具核对。不可用于正式题库。",
    );
    unitIds.push(`generated.${id}`);
    for (const [user, character] of [
      [user0, char0],
      [user1, char1],
    ] as const) {
      const started = await engine.inspect(user, (s) => s.start(character, "primary3"));
      expect(started.attempt?.unit.id).toBe(`generated.${id}`);
    }
    await repository.publish(
      id,
      String(job.candidate_hash),
      fixture.blueprint,
      "测试审核者",
      "重复发布只返回已有成功结果，不新增版本、题目、奖励或者其他内容记录。",
    );
    expect(
      await database.sql`select * from app.learning_unit_versions where unit_id=${`generated.${id}`}`,
    ).toHaveLength(1);
  });
  it("租约过期旧结果不能覆盖；失败退避、三次封顶与每日预算生效", async () => {
    const id = randomUUID(),
      fixture = await generationFixture(id),
      role = `test.${id}`;
    const blueprint = { ...fixture.blueprint, roleKey: role };
    fixture.unit.roleKey = role;
    await enqueue(id, role);
    const lease = await repository.claim([blueprint], 50);
    if (!lease) throw new Error("未取得租约。");
    await database.sql`update app.learning_generation_jobs set lease_until=now()-interval '1 second' where id=${id}`;
    const newer = await repository.claim([blueprint], 50);
    if (!newer) throw new Error("未回收过期租约。");
    expect(await repository.stage(lease, fixture.unit, fixture.report)).toBe(false);
    await repository.fail(newer, "TEST_FAILURE");
    expect(await repository.claim([blueprint], 50)).toBeUndefined();
    await database.sql`update app.learning_generation_jobs set available_at=now() where id=${id}`;
    expect(await repository.claim([blueprint], 1)).toBeUndefined();
    const last = await repository.claim([blueprint], 50);
    if (!last) throw new Error("未取得最后一次租约。");
    expect(last.attempt).toBe(3);
    await repository.fail(last, "TEST_FAILURE");
    expect((await repository.inspect(id)).status).toBe("failed");
    expect(await repository.claim([blueprint], 50)).toBeUndefined();
  });
  it("私有角色没有蓝图不调用模型；协议失败不进入待审", async () => {
    const id = randomUUID();
    await enqueue(id, `character.${randomUUID()}`);
    const complete = vi.fn(() =>
      Promise.resolve({
        content: "{}",
        model: "fixture",
        usage: {},
      }),
    );
    expect(
      await createLearningGenerationProcessor(repository, [], complete, 50).runOnce(),
    ).toBe("idle");
    expect(complete).not.toHaveBeenCalled();
    const other = randomUUID(),
      fixture = await generationFixture(other),
      role = `test.${other}`;
    await enqueue(other, role);
    expect(
      await createLearningGenerationProcessor(
        repository,
        [{ ...fixture.blueprint, roleKey: role }],
        complete,
        50,
      ).runOnce(),
    ).toBe("failed");
    const job = await repository.inspect(other);
    expect(job.status).toBe("pending");
    expect(job.candidate).toBeNull();
  });
  it("发布时再次去重，复刻内容不能成为新共享题", async () => {
    const id = randomUUID(),
      fixture = await generationFixture(id),
      role = `test.${id}`;
    const blueprint = { ...fixture.blueprint, roleKey: role };
    fixture.unit.roleKey = role;
    await enqueue(id, role);
    const lease = await repository.claim([blueprint], 50);
    if (!lease) throw new Error("缺少租约。");
    await repository.stage(lease, fixture.unit, fixture.report);
    const clone = { ...fixture.unit, id: `test.original.${id}` };
    unitIds.push(clone.id);
    await new LearningEngineRepository(database).publish(clone);
    await expect(
      repository.publish(
        id,
        contentHash(fixture.unit),
        blueprint,
        "测试审核者",
        "测试发布时必须重查已有内容，避免审核期间另一个编辑发布了重复题目。",
      ),
    ).rejects.toThrow();
    expect((await repository.inspect(id)).status).toBe("review");
  });
  it("独立审核拒绝保留候选和反例证据，不发布；最终过期租约结束审计", async () => {
    const id = randomUUID(),
      fixture = await generationFixture(id),
      role = `test.${id}`;
    await enqueue(id, role);
    fixture.report.levelFits = false;
    const complete = (input: { phase: "author" | "review" }) =>
      Promise.resolve({
        content:
          input.phase === "author" ? fixture.draft : JSON.stringify(fixture.report),
        model: "工程夹具",
        usage: { inputTokens: 10, outputTokens: 10 },
      });
    expect(
      await createLearningGenerationProcessor(
        repository,
        [{ ...fixture.blueprint, roleKey: role }],
        complete,
        50,
      ).runOnce(),
    ).toBe("failed");
    const job = await repository.inspect(id);
    expect(job.candidate).not.toBeNull();
    expect(job.status).toBe("pending");
    const [run] =
      await database.sql`select candidate,review_report,error_code from app.learning_generation_runs where job_id=${id}`;
    expect(run?.candidate).not.toBeNull();
    expect(run?.review_report).toMatchObject({ levelFits: false });
    expect(run?.error_code).toBe("INDEPENDENT_REVIEW_FAILED");
    await database.sql`update app.learning_generation_jobs set status='running',attempts=3,lease_until=now()-interval '1 second' where id=${id}`;
    await database.sql`update app.learning_generation_runs set attempt=3,outcome='running' where job_id=${id}`;
    expect(
      await repository.claim([{ ...fixture.blueprint, roleKey: role }], 50),
    ).toBeUndefined();
    expect((await repository.inspect(id)).status).toBe("failed");
    const [expired] =
      await database.sql`select outcome from app.learning_generation_runs where job_id=${id}`;
    expect(expired?.outcome).toBe("expired");
  });
});
