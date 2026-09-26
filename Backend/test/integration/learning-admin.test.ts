import { randomUUID } from "node:crypto";
import { Script } from "node:vm";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { createAdminAuthenticator } from "../../src/modules/admin/http.js";
import { LearningAdminRepository } from "../../src/modules/learning/admin-repository.js";
import { LearningAdminService } from "../../src/modules/learning/admin-service.js";
import { registerLearningAdminRoutes } from "../../src/modules/learning/admin-routes.js";
import { registerLearningAdminConsole } from "../../src/modules/learning/admin-console.js";
import { LearningGenerationRepository } from "../../src/modules/learning/generation-repository.js";
import { LearningEngineRepository } from "../../src/modules/learning/engine-repository.js";
import { createLearningGenerationProcessor } from "../../src/modules/learning/generation-processor.js";
import { contentHash } from "../../src/modules/learning/content.js";
import type { GenerationBlueprint } from "../../src/modules/learning/generation-content.js";
import { generationFixture } from "../helpers/learning-generation.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")("挑战内容工作台", () => {
  let app: FastifyInstance;
  let database: DatabaseResource;
  let generation: LearningGenerationRepository;
  const blueprints: GenerationBlueprint[] = [];
  const jobs: string[] = [],
    units: string[] = [];
  const token = "learning-admin-isolated-test-token-only";
  const auth = { authorization: `Bearer ${token}` };
  const notes =
    "隔离测试中的逐题审核：题干条件完整、答案与解析一致、提示不泄题，修改稿必须重新审题。";
  const base = "/internal/admin/learning";
  beforeAll(async () => {
    const config = integrationConfig({
      ADMIN_API_ENABLED: "true",
      ADMIN_API_KEYS: `content-editor=${token}`,
    });
    database = createDatabase(config);
    await runMigrations(database);
    generation = new LearningGenerationRepository(database);
    app = await buildApp(config, { logger: false });
    registerLearningAdminConsole(app);
    registerLearningAdminRoutes(
      app,
      createAdminAuthenticator(config.adminApiKeys),
      new LearningAdminService(
        new LearningAdminRepository(database),
        generation,
        blueprints,
      ),
    );
    await app.ready();
  });
  afterAll(async () => {
    await app.close();
    for (const id of jobs)
      await database.sql`delete from app.learning_generation_edits where source_job_id=${id} or revised_job_id=${id}`;
    for (const id of jobs) {
      await database.sql`delete from app.learning_generation_runs where job_id=${id}`;
      await database.sql`delete from app.learning_generation_jobs where id=${id}`;
      units.push(`generated.${id}`);
    }
    for (const id of units) {
      await database.sql`delete from app.learning_unit_versions where unit_id=${id}`;
      await database.sql`delete from app.learning_units where id=${id}`;
    }
    await database.close();
  });
  const get = (path: string) => app.inject({ url: base + path, headers: auth });
  const post = (id: string, action: string, payload: Record<string, unknown>) =>
    app.inject({
      method: "POST",
      url: `${base}/jobs/${id}/${action}`,
      headers: auth,
      payload,
    });
  async function draft(status: "failed" | "review") {
    const id = randomUUID(),
      fixture = await generationFixture(id);
    jobs.push(id);
    fixture.blueprint = { ...fixture.blueprint, roleKey: `test.${id}` };
    fixture.unit.roleKey = fixture.blueprint.roleKey;
    blueprints.push(fixture.blueprint);
    await database.sql`insert into app.learning_generation_jobs(id,role_key,level_key) values(${id},${fixture.unit.roleKey},${fixture.unit.level})`;
    const lease = await generation.claim([fixture.blueprint], 50);
    if (!lease) throw new Error("缺少测试租约。");
    await generation.recordCandidate(lease, fixture.unit);
    if (status === "review")
      await generation.stage(lease, fixture.unit, fixture.report);
    else await generation.fail(lease, "TEST_REJECTED", false);
    return { id, fixture, hash: contentHash(fixture.unit) };
  }
  it("静态页面无凭据与课程答案，接口必须鉴权，脚本语法有效", async () => {
    const page = await app.inject({ url: base });
    expect(page.statusCode).toBe(200);
    expect(page.body).toContain("挑战内容");
    expect(page.body).not.toContain(token);
    expect(page.headers["content-security-policy"]).toContain("default-src 'none'");
    for (const path of ["/units", "/jobs", `/jobs/${randomUUID()}`, "/units/example"]) {
      expect((await app.inject({ url: base + path })).statusCode).toBe(401);
      expect(
        (
          await app.inject({
            url: base + path,
            headers: { authorization: "Bearer incorrect" },
          })
        ).statusCode,
      ).toBe(401);
    }
    expect(
      (
        await app.inject({
          method: "POST",
          url: `${base}/jobs/${randomUUID()}/publish`,
          payload: {},
        })
      ).statusCode,
    ).toBe(401);
    const js = await app.inject({ url: base + "/console.js" });
    expect(js.statusCode).toBe(200);
    expect(() => new Script(js.body)).not.toThrow();
    expect(js.body).not.toContain("innerHTML");
    expect((await app.inject({ url: base + "/console.css" })).statusCode).toBe(200);
    expect((await get("/units?limit=51")).statusCode).toBe(400);
    expect((await get("/units?level=unknown")).statusCode).toBe(400);
  });
  it("正式单元按角色与水平筛选，能读取不可变历史版本", async () => {
    const { unit } = await generationFixture(randomUUID());
    unit.id = `test.${randomUUID()}`;
    unit.roleKey = unit.id;
    units.push(unit.id);
    const engine = new LearningEngineRepository(database);
    await engine.publish(unit);
    await engine.publish({ ...unit, version: 2, title: "第二版标题" });
    const list = await get(`/units?role=${unit.roleKey}&level=primary3&limit=1`);
    expect(list.json()).toMatchObject({
      total: 1,
      items: [{ id: unit.id, current_version: 2 }],
    });
    const original = await get(`/units/${unit.id}?version=1`);
    expect(original.json()).toMatchObject({
      unit,
      currentVersion: 2,
      versions: [{ version: 2 }, { version: 1 }],
    });
    expect((await get(`/units/${unit.id}`)).json()).toMatchObject({
      unit: { title: "第二版标题" },
    });
    expect((await get(`/units/${unit.id}?version=3`)).statusCode).toBe(404);
    expect(
      (
        await app.inject({
          method: "PUT",
          url: `${base}/units/${unit.id}`,
          headers: auth,
          payload: unit,
        })
      ).statusCode,
    ).toBe(404);
  });
  it("发布绑定审核者、确认与内容指纹，并发发布保持单一版本", async () => {
    const { id, hash } = await draft("review");
    const payload = { candidateHash: hash, notes, confirmed: true };
    expect((await post(id, "publish", { candidateHash: hash, notes })).statusCode).toBe(
      400,
    );
    expect(
      (await post(id, "publish", { ...payload, editor: "伪造审核者" })).statusCode,
    ).toBe(400);
    expect(
      (await post(id, "publish", { ...payload, candidateHash: "0".repeat(64) }))
        .statusCode,
    ).toBe(409);
    const results = await Promise.all([
      post(id, "publish", payload),
      post(id, "publish", payload),
    ]);
    expect(results.map((r) => r.statusCode)).toEqual([200, 200]);
    const job = await get(`/jobs/${id}`);
    expect(job.json()).toMatchObject({
      status: "published",
      reviewed_by: "管理员 content-editor",
      review_notes: notes,
    });
    expect((await get(`/units/generated.${id}`)).json()).toMatchObject({
      unit: { authorship: { reviewedBy: "管理员 content-editor" } },
      versions: [{ version: 1 }],
    });
    expect((await post(id, "reject", payload)).statusCode).toBe(409);
  });
  it("失败稿修订幂等且保留原稿，必须重新独立审题才能进入审核", async () => {
    const { id, hash, fixture } = await draft("failed");
    const body = {
      requestId: randomUUID(),
      candidateHash: hash,
      notes,
      unit: { ...fixture.unit, title: "修订后的标题" },
    };
    expect(
      (await post(id, "publish", { candidateHash: hash, notes, confirmed: true }))
        .statusCode,
    ).toBe(409);
    expect(
      (
        await post(id, "revisions", {
          ...body,
          unit: { ...body.unit, roleKey: "other" },
        })
      ).statusCode,
    ).toBe(409);
    const created = await post(id, "revisions", body);
    expect(created.statusCode, created.body).toBe(200);
    const revised = created.json<{ revisedJobId: string }>().revisedJobId;
    jobs.push(revised);
    expect((await post(id, "revisions", body)).json()).toEqual(created.json());
    expect(
      (await post(id, "revisions", { ...body, notes: notes + "变更" })).statusCode,
    ).toBe(409);
    expect((await get(`/jobs/${id}`)).json()).toMatchObject({
      candidate: fixture.unit,
      last_error_code: "EDITOR_REVISED",
      edits: [{ editor: "管理员 content-editor", revised_job_id: revised }],
    });
    expect((await get(`/jobs/${revised}`)).json()).toMatchObject({
      status: "pending",
      isRevision: true,
      canRevise: false,
      previewUnit: { title: "修订后的标题" },
    });
    expect((await get(`/jobs/${id}`)).json()).toMatchObject({ canRevise: false });
    const processor = createLearningGenerationProcessor(
      generation,
      [fixture.blueprint],
      (request) => {
        expect(request.phase).toBe("review");
        return Promise.resolve({
          content: JSON.stringify(fixture.report),
          model: "隔离工程复审",
          usage: {},
        });
      },
      50,
    );
    expect(await processor.runOnce()).toBe("review");
    const detail = (await get(`/jobs/${revised}`)).json<{ candidate_hash: string }>();
    expect(
      (
        await post(revised, "reject", {
          candidateHash: detail.candidate_hash,
          notes,
          confirmed: true,
        })
      ).statusCode,
    ).toBe(200);
    expect((await get(`/jobs/${revised}`)).json()).toMatchObject({
      status: "failed",
      reviewed_by: "管理员 content-editor",
      review_notes: notes,
    });
    expect(
      (await get(`/jobs?role=${fixture.blueprint.roleKey}&status=failed`)).json(),
    ).toMatchObject({ total: 2 });
  });
});
