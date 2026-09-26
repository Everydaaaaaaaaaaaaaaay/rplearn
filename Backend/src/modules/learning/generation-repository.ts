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
  editorDraft?: LearningUnit;
  editor?: string;
}>;
interface GenerationJob {
  id: string;
  role_key: string;
  level_key: LearningUnit["level"];
  status: string;
  attempts: number;
  candidate_hash: string | null;
  blueprint_hash: string | null;
  candidate: unknown;
  review_report: unknown;
  last_error_code: string | null;
  reviewed_by: string | null;
  review_notes: string | null;
  published_unit_id: string | null;
}
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
          {
            id: string;
            attempts: number;
            editor_payload: unknown;
            editor: string | null;
            editor_blueprint_hash: string | null;
          }[]
        >`select j.id,j.attempts,e.payload as editor_payload,e.editor,e.blueprint_hash as editor_blueprint_hash from app.learning_generation_jobs j left join app.learning_generation_edits e on e.revised_job_id=j.id where j.role_key=${blueprint.roleKey} and j.level_key=${blueprint.level} and j.available_at<=now() and j.attempts<3 and (j.status='pending' or (j.status='running' and j.lease_until<now())) order by j.created_at for update of j skip locked limit 1`;
        if (!job) continue;
        if (job.editor !== null && job.editor_blueprint_hash !== blueprint.hash) {
          await sql`update app.learning_generation_runs set outcome='expired',finished_at=now(),error_code='EDITOR_BLUEPRINT_CHANGED' where job_id=${job.id} and outcome='running'`;
          await sql`update app.learning_generation_jobs set status='failed',last_error_code='EDITOR_BLUEPRINT_CHANGED',lease_until=null,lease_token=null where id=${job.id}`;
          continue;
        }
        const token = randomUUID(),
          attempt = job.attempts + 1;
        await sql`update app.learning_generation_runs set outcome='expired',finished_at=now(),error_code='LEASE_EXPIRED' where job_id=${job.id} and outcome='running'`;
        await sql`update app.learning_generation_jobs set status='running',attempts=${attempt},lease_token=${token},lease_until=now()+interval '5 minutes',blueprint_hash=${blueprint.hash},candidate=null,candidate_hash=null,review_report=null where id=${job.id}`;
        await sql`insert into app.learning_generation_runs(job_id,attempt,lease_token,blueprint_hash,prompt_version) values(${job.id},${attempt},${token},${blueprint.hash},${generationPromptVersion})`;
        return {
          id: job.id,
          attempt,
          token,
          blueprint,
          ...(job.editor !== null
            ? { editorDraft: unitSchema.parse(job.editor_payload), editor: job.editor }
            : {}),
        };
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
  async recordOutput(
    lease: GenerationLease,
    phase: "author" | "review",
    content: string,
  ): Promise<void> {
    const evidence = JSON.stringify({
      rawResponse: content.slice(0, 10000),
      truncated: content.length > 10000,
    });
    if (phase === "author")
      await this.database
        .sql`update app.learning_generation_runs set candidate=${evidence}::jsonb where job_id=${lease.id} and attempt=${lease.attempt} and lease_token=${lease.token}`;
    else
      await this.database
        .sql`update app.learning_generation_runs set review_report=${evidence}::jsonb where job_id=${lease.id} and attempt=${lease.attempt} and lease_token=${lease.token}`;
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
  async fail(lease: GenerationLease, code: string, retryable = true): Promise<void> {
    await this.database.sql.begin(async (sql) => {
      const changed =
        await sql`update app.learning_generation_jobs set status=${!retryable || lease.attempt >= 3 ? "failed" : "pending"},last_error_code=${code},available_at=now()+${String(60 * 5 ** lease.attempt)}::int*interval '1 second',lease_until=null,lease_token=null where id=${lease.id} and status='running' and lease_token=${lease.token} returning id`;
      if (changed.length)
        await sql`update app.learning_generation_runs set outcome='failed',error_code=${code},finished_at=now() where job_id=${lease.id} and attempt=${lease.attempt}`;
    });
  }
  async list() {
    return this.database
      .sql`select id,role_key,level_key,status,attempts,candidate_hash,last_error_code,created_at from app.learning_generation_jobs order by created_at desc limit 100`;
  }
  async inspect(id: string) {
    const [row] = await this.database.sql<
      GenerationJob[]
    >`select id,role_key,level_key,status,attempts,candidate_hash,blueprint_hash,candidate,review_report,last_error_code,reviewed_by,review_notes,published_unit_id from app.learning_generation_jobs where id=${id}`;
    if (!row) throw new Error("找不到生成任务。");
    const runs = await this.database
      .sql`select attempt,prompt_version,blueprint_hash,author_model,review_model,author_usage,review_usage,outcome,error_code,candidate,review_report,created_at,finished_at from app.learning_generation_runs where job_id=${id} order by attempt`;
    const edits = await this.database
      .sql`select id,source_job_id,source_candidate_hash,revised_job_id,blueprint_hash,editor,notes,content_hash,created_at from app.learning_generation_edits where source_job_id=${id} or revised_job_id=${id} order by created_at`;
    return { ...row, runs, edits };
  }
  /** 修订形成新的待审任务；原稿、尝试与失败报告保留，预算仍走同一领取入口。 */
  async revise(
    input: {
      requestId: string;
      sourceJobId: string;
      candidateHash: string;
      editor: string;
      notes: string;
      unit: unknown;
    },
    blueprint: GenerationBlueprint,
  ): Promise<string> {
    const requestHash = contentHash(input);
    const editor = input.editor.trim(),
      notes = input.notes.trim();
    if (
      editor.length < 2 ||
      editor.length > 60 ||
      notes.length < 30 ||
      notes.length > 1000
    )
      throw new Error("修订必须填写实际编辑者及 30 至 1000 字符的具体变更说明。");
    return await this.database.sql.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(hashtextextended(${`learning-edit:${input.requestId}`},0))`;
      const [receipt] = await sql<
        { request_hash: string; revised_job_id: string }[]
      >`select request_hash,revised_job_id from app.learning_generation_edits where id=${input.requestId}`;
      if (receipt) {
        if (receipt.request_hash !== requestHash)
          throw new Error("修订请求标识已用于不同内容。");
        return receipt.revised_job_id;
      }
      await sql`select pg_advisory_xact_lock(hashtextextended('learning-publication',0))`;
      const [source] = await sql<
        GenerationJob[]
      >`select * from app.learning_generation_jobs where id=${input.sourceJobId} for update`;
      if (
        !source ||
        !["failed", "review", "pending"].includes(source.status) ||
        source.candidate_hash !== input.candidateHash ||
        source.blueprint_hash !== blueprint.hash
      )
        throw new Error("原稿已变更、正在处理或已经发布，不能直接修订。");
      const [previous] =
        await sql`select id from app.learning_generation_edits where source_job_id=${input.sourceJobId} and source_candidate_hash=${input.candidateHash}`;
      if (previous) throw new Error("这个原稿已有修订任务，请继续处理其新版本。");
      const old = unitSchema.parse(source.candidate),
        proposed = unitSchema.parse(input.unit);
      if (
        old.id !== proposed.id ||
        proposed.id !== `generated.${source.id}` ||
        source.role_key !== blueprint.roleKey ||
        source.level_key !== blueprint.level ||
        proposed.roleKey !== old.roleKey ||
        proposed.level !== old.level ||
        proposed.version !== old.version
      )
        throw new Error("修订不能更换单元身份、角色或水平。");
      const revisedJobId = randomUUID();
      const unit = unitSchema.parse({
        ...proposed,
        id: `generated.${revisedJobId}`,
        authorship: {
          kind: "generated",
          author: `服务端生成；${editor}修订`,
          reviewedBy: "待重新审题与发布复核",
          reviewedAt: new Date().toISOString().slice(0, 10),
          reviewNotes: notes,
        },
      });
      const rows = await sql<
        { payload: unknown }[]
      >`select v.payload from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where u.role_key=${blueprint.roleKey} and u.level_key=${blueprint.level}`;
      validateGeneratedUnit(
        unit,
        blueprint,
        rows.map((r) => unitSchema.parse(r.payload)),
      );
      const [busy] =
        await sql`select id from app.learning_generation_jobs where role_key=${blueprint.roleKey} and level_key=${blueprint.level} and status in ('pending','running','review') and id<>${source.id}`;
      if (busy) throw new Error("该角色与水平已有其他补库任务，请先处理现有任务。");
      await sql`update app.learning_generation_jobs set status='failed',last_error_code='EDITOR_REVISED',lease_until=null,lease_token=null where id=${source.id}`;
      await sql`insert into app.learning_generation_jobs(id,role_key,level_key,blueprint_hash) values(${revisedJobId},${blueprint.roleKey},${blueprint.level},${blueprint.hash})`;
      await sql`insert into app.learning_generation_edits(id,request_hash,source_job_id,source_candidate_hash,revised_job_id,blueprint_hash,editor,notes,payload,content_hash) values(${input.requestId},${requestHash},${source.id},${input.candidateHash},${revisedJobId},${blueprint.hash},${editor},${notes},${JSON.stringify(unit)}::jsonb,${contentHash(unit)})`;
      return revisedJobId;
    });
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
