import { randomUUID } from "node:crypto";
import type { DatabaseResource } from "../../db/client.js";
import { contentHash, unitSchema, type LearningUnit } from "./content.js";
import { LearningEngineRepository } from "./engine-repository.js";
import {
  generationPromptVersion,
  validateGeneratedUnit,
  validateIndependentReview,
  type GenerationBlueprint,
  type UnitSummary,
} from "./generation-content.js";

export type GenerationLease = Readonly<{
  id: string;
  attempt: number;
  token: string;
  blueprint: GenerationBlueprint;
}>;
export class LearningGenerationRepository {
  constructor(private readonly database: DatabaseResource) {}
  async claim(
    blueprints: readonly GenerationBlueprint[],
    dailyJobs: number,
  ): Promise<GenerationLease | undefined> {
    if (!Number.isInteger(dailyJobs) || dailyJobs < 1 || dailyJobs > 50)
      throw new Error("生成预算必须在 1 至 50 之间。");
    return await this.database.sql.begin(async (sql) => {
      // 跨 Worker 共用预算锁；一次租约预留作者与审题两次请求，崩溃也不退预算。
      await sql`select pg_advisory_xact_lock(hashtextextended('learning-generation-budget',0))`;
      await sql`update app.learning_generation_runs r set outcome='expired',finished_at=now(),error_code='LEASE_EXHAUSTED' from app.learning_generation_jobs j where r.job_id=j.id and r.attempt=j.attempts and r.outcome='running' and j.status='running' and j.lease_until<now() and j.attempts>=3`;
      await sql`update app.learning_generation_jobs set status='failed', last_error_code='LEASE_EXHAUSTED',lease_until=null,lease_token=null where status='running' and lease_until<now() and attempts>=3`;
      const [budget] = await sql<
        { count: number }[]
      >`select count(*)::int as count from app.learning_generation_runs where created_at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'`;
      if ((budget?.count ?? 0) >= dailyJobs) return undefined;
      for (const blueprint of blueprints) {
        const [job] = await sql<
          { id: string; attempts: number }[]
        >`select id,attempts from app.learning_generation_jobs where role_key=${blueprint.roleKey} and level_key=${blueprint.level} and available_at<=now() and attempts<3 and (status='pending' or (status='running' and lease_until<now())) order by created_at for update skip locked limit 1`;
        if (!job) continue;
        const token = randomUUID(),
          attempt = job.attempts + 1;
        await sql`update app.learning_generation_runs set outcome='expired',finished_at=now(),error_code='LEASE_EXPIRED' where job_id=${job.id} and outcome='running'`;
        await sql`update app.learning_generation_jobs set status='running',attempts=${attempt},lease_token=${token},lease_until=now()+interval '5 minutes',blueprint_hash=${blueprint.hash},candidate=null,candidate_hash=null,review_report=null where id=${job.id}`;
        await sql`insert into app.learning_generation_runs(job_id,attempt,lease_token,blueprint_hash,prompt_version) values(${job.id},${attempt},${token},${blueprint.hash},${generationPromptVersion})`;
        return { id: job.id, attempt, token, blueprint };
      }
      return undefined;
    });
  }
  async existing(
    roleKey: string,
    level: LearningUnit["level"],
  ): Promise<readonly UnitSummary[]> {
    const rows = await this.database.sql<
      { payload: unknown }[]
    >`select v.payload from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where u.role_key=${roleKey} and u.level_key=${level}`;
    return rows.map((r) => unitSchema.parse(r.payload));
  }
  async recordCall(
    lease: GenerationLease,
    phase: "author" | "review",
    model: string,
    usage: unknown,
  ): Promise<void> {
    if (phase === "author")
      await this.database
        .sql`update app.learning_generation_runs set author_model=${model},author_usage=${JSON.stringify(usage)}::jsonb where job_id=${lease.id} and attempt=${lease.attempt} and lease_token=${lease.token}`;
    else
      await this.database
        .sql`update app.learning_generation_runs set review_model=${model},review_usage=${JSON.stringify(usage)}::jsonb where job_id=${lease.id} and attempt=${lease.attempt} and lease_token=${lease.token}`;
  }
  async recordCandidate(lease: GenerationLease, unit: LearningUnit): Promise<boolean> {
    return await this.database.sql.begin(async (sql) => {
      const changed =
        await sql`update app.learning_generation_jobs set candidate=${JSON.stringify(unit)}::jsonb,candidate_hash=${contentHash(unit)} where id=${lease.id} and status='running' and lease_token=${lease.token} and lease_until>now() returning id`;
      if (!changed.length) return false;
      await sql`update app.learning_generation_runs set candidate=${JSON.stringify(unit)}::jsonb where job_id=${lease.id} and attempt=${lease.attempt}`;
      return true;
    });
  }
  async recordReview(lease: GenerationLease, report: unknown): Promise<void> {
    await this.database
      .sql`update app.learning_generation_runs set review_report=${JSON.stringify(report)}::jsonb where job_id=${lease.id} and attempt=${lease.attempt} and lease_token=${lease.token}`;
  }
  async stage(
    lease: GenerationLease,
    unit: LearningUnit,
    report: unknown,
  ): Promise<boolean> {
    return await this.database.sql.begin(async (sql) => {
      const changed =
        await sql`update app.learning_generation_jobs set status='review',candidate=${JSON.stringify(unit)}::jsonb,candidate_hash=${contentHash(unit)},review_report=${JSON.stringify(report)}::jsonb,lease_until=null,lease_token=null,last_error_code=null where id=${lease.id} and status='running' and lease_token=${lease.token} and lease_until>now() returning id`;
      if (!changed.length) return false;
      await sql`update app.learning_generation_runs set outcome='review',finished_at=now() where job_id=${lease.id} and attempt=${lease.attempt}`;
      return true;
    });
  }
  async fail(lease: GenerationLease, code: string): Promise<void> {
    await this.database.sql.begin(async (sql) => {
      const changed =
        await sql`update app.learning_generation_jobs set status=${lease.attempt >= 3 ? "failed" : "pending"},last_error_code=${code},available_at=now()+${String(60 * 5 ** lease.attempt)}::int*interval '1 second',lease_until=null,lease_token=null where id=${lease.id} and status='running' and lease_token=${lease.token} returning id`;
      if (changed.length)
        await sql`update app.learning_generation_runs set outcome='failed',error_code=${code},finished_at=now() where job_id=${lease.id} and attempt=${lease.attempt}`;
    });
  }
  async list() {
    return this.database
      .sql`select id,role_key,level_key,status,attempts,candidate_hash,last_error_code,created_at from app.learning_generation_jobs order by created_at desc limit 100`;
  }
  async inspect(id: string) {
    const [row] = await this.database
      .sql`select id,role_key,level_key,status,attempts,candidate_hash,blueprint_hash,candidate,review_report,last_error_code,reviewed_by,review_notes,published_unit_id from app.learning_generation_jobs where id=${id}`;
    if (!row) throw new Error("找不到生成任务。");
    return row;
  }
  async publish(
    id: string,
    expectedHash: string,
    blueprint: GenerationBlueprint,
    reviewer: string,
    notes: string,
  ): Promise<void> {
    if (reviewer.trim().length < 2 || notes.trim().length < 30)
      throw new Error("必须登记实际复核者与逐题复核结论。");
    await this.database.sql.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(hashtextextended('learning-publication',0))`;
      const [job] =
        await sql`select * from app.learning_generation_jobs where id=${id} for update`;
      if (job?.candidate_hash !== expectedHash || job.blueprint_hash !== blueprint.hash)
        throw new Error("候选或蓝图已变更，请重新复核当前哈希。");
      if (job.status === "published") return;
      if (job.status !== "review") throw new Error("只有待审候选可以发布。");
      const rows = await sql<
        { payload: unknown }[]
      >`select v.payload from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where u.role_key=${blueprint.roleKey} and u.level_key=${blueprint.level}`;
      const unit = validateGeneratedUnit(
        job.candidate,
        blueprint,
        rows.map((r) => unitSchema.parse(r.payload)),
      );
      if (contentHash(unit) !== expectedHash || unit.id !== `generated.${id}`)
        throw new Error("候选身份或内容哈希不符。");
      validateIndependentReview(JSON.stringify(job.review_report), unit);
      unit.authorship.reviewedBy = reviewer.trim();
      unit.authorship.reviewedAt = new Date().toISOString().slice(0, 10);
      unit.authorship.reviewNotes = notes.trim();
      await new LearningEngineRepository(this.database).publishInTransaction(
        sql,
        unitSchema.parse(unit),
      );
      await sql`update app.learning_generation_jobs set status='published',reviewed_by=${reviewer.trim()},review_notes=${notes.trim()},published_unit_id=${unit.id} where id=${id}`;
      await sql`update app.learning_generation_runs set outcome='published' where job_id=${id} and attempt=${Number(job.attempts)}`;
    });
  }
  async reject(
    id: string,
    expectedHash: string,
    notes: string,
    reviewer: string,
  ): Promise<void> {
    if (reviewer.trim().length < 2 || notes.trim().length < 15)
      throw new Error("退回必须说明具体质量缺陷。");
    const rows = await this.database
      .sql`update app.learning_generation_jobs set status='failed',last_error_code='EDITOR_REJECTED',review_notes=${notes},reviewed_by=${reviewer} where id=${id} and status='review' and candidate_hash=${expectedHash} returning id`;
    if (!rows.length) throw new Error("候选状态或哈希已改变。");
  }
}
