import { availableForNewLearning } from "./bank-content.js";
import { ZodError } from "zod";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import {
  contentHash,
  questionAudios,
  unitSchema,
  type LearningLevel,
  type LearningUnit,
} from "./content.js";
import {
  assembleBankQuestions,
  bankBlueprintSchema,
  bankQuestionSchema,
  bankCatalogRevisionSchema,
  type BankCatalogRevision,
  bankIdentity,
  bankUnit,
  type BankBlueprint,
  type BankCandidate,
  type BankQuestion,
} from "./bank-content.js";

function conflict(message: string): never {
  throw new AppError({ code: "LEARNING_BANK_CONFLICT", message, statusCode: 409 });
}
function validateRevision(old: BankQuestion, q: BankQuestion) {
  if (
    q.level !== old.level ||
    q.question.goalId !== old.question.goalId ||
    q.question.type !== old.question.type ||
    contentHash(q.references) !== contentHash(old.references)
  )
    conflict("修订必须递增版本，并保留年级、目标、题型和来源；新教学目标应另建题目。");
  // 当前后台修订不接收新媒体；避免未验证的录音或图片进入正式库。
  const media = (question: BankQuestion) => ({
    audio: questionAudios(question.question),
    images: JSON.stringify(question.question).match(/image\.[a-f0-9]{64}/g) ?? [],
  });
  if (contentHash(media(q)) !== contentHash(media(old)))
    conflict("媒体修订需要经过素材校验，不能在此替换。");
  // 复用完整单元验证，检查选项、正确答案和词块引用。
  try {
    unitSchema.parse(
      bankUnit(
        {
          id: "validation",
          title: "题目校验",
          level: q.level,
          topic: q.topic,
          prerequisiteGoalIds: [],
          slots: Array.from({ length: 6 }, () => ({
            goalId: q.question.goalId,
            type: q.question.type,
          })),
        },
        Array.from({ length: 6 }, (_, i) => ({ ...q, id: `validation.q${String(i)}` })),
        "validation",
        "validation",
        "校验",
      ),
    );
  } catch (error) {
    if (error instanceof ZodError)
      throw new AppError({
        code: "LEARNING_CONTENT_INVALID",
        message: "题目答案、选项或词块引用无效，请检查后再发布。",
        statusCode: 422,
      });
    throw error;
  }
}

export class LearningBankSession {
  constructor(
    private readonly sql: TransactionSql,
    private readonly userId: string,
  ) {}

  async pool(level: LearningLevel) {
    const rows = await this.sql<
      { payload: BankQuestion; seen: boolean; mastered: boolean; review_due: boolean }[]
    >`
      select v.payload,
        exists(select 1 from app.learning_bank_exposures e where e.user_id=${this.userId} and e.question_id=q.id) as seen,
        exists(select 1 from app.learning_bank_mastery m where m.user_id=${this.userId} and m.question_id=q.id) as mastered,
        coalesce((select max(e.created_at) < now() - interval '7 days' from app.learning_bank_exposures e where e.user_id=${this.userId} and e.question_id=q.id),false) and exists(select 1 from app.learning_bank_mastery m where m.user_id=${this.userId} and m.question_id=q.id and m.created_at<now()-interval '7 days') as review_due
      from app.learning_bank_questions q join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version
      where q.published and v.payload->>'level'=${level}`;
    const blueprints = await this.sql<
      { payload: BankBlueprint }[]
    >`select payload from app.learning_bank_blueprints where published and payload->>'level'=${level} order by id`;
    const goals = await this.sql<
      { goal_id: string }[]
    >`select distinct goal_id from app.learning_rewards where user_id=${this.userId}`;
    return {
      candidates: rows.map((r): BankCandidate => ({
        ...bankQuestionSchema.parse(r.payload),
        seen: r.seen,
        mastered: r.mastered,
        reviewDue: r.review_due,
      })),
      blueprints: blueprints.map((r) => bankBlueprintSchema.parse(r.payload)),
      coveredGoals: new Set(goals.map((r) => r.goal_id)),
    };
  }

  async choices(level: LearningLevel, roleKey: string) {
    const [control] = await this.sql<
      { enabled: boolean }[]
    >`select enabled from app.learning_bank_control where id=true`;
    if (!control?.enabled) return [];
    const pool = await this.pool(level);
    return pool.blueprints.flatMap((blueprint) => {
      const questions = assembleBankQuestions(
        blueprint,
        pool.candidates,
        roleKey,
        pool.coveredGoals,
      );
      return questions
        ? [
            {
              blueprint,
              questions,
              reviewOnly: questions.every(
                (q) => pool.candidates.find((c) => c.id === q.id)?.mastered,
              ),
              priority:
                questions.filter(
                  (q) => !pool.candidates.find((c) => c.id === q.id)?.mastered,
                ).length *
                  10 +
                blueprint.slots.filter((slot) => !pool.coveredGoals.has(slot.goalId))
                  .length,
            },
          ]
        : [];
    });
  }

  async compose(
    level: LearningLevel,
    roleKey: string,
    name: string,
    attemptId: string,
    options: { minQuestions?: number; excludeReviewOnly?: boolean } = {},
  ) {
    const choices = (await this.choices(level, roleKey)).filter(
      (choice) =>
        choice.questions.length >= (options.minQuestions ?? 0) &&
        !(options.excludeReviewOnly && choice.reviewOnly),
    );
    if (!choices.length) return null;
    const priority = Math.max(...choices.map((choice) => choice.priority));
    const preferred = choices.filter((choice) => choice.priority === priority);
    const choice = preferred[Math.floor(Math.random() * preferred.length)];
    if (!choice) return null;
    return {
      unit: bankUnit(
        {
          ...choice.blueprint,
          title: choice.reviewOnly
            ? `复习 · ${choice.blueprint.title}`
            : choice.blueprint.title,
        },
        choice.questions,
        `assembled.${attemptId}`,
        roleKey,
        name,
      ),
      questions: choice.questions,
      blueprintId: choice.blueprint.id,
    };
  }

  async recordExposure(
    attemptId: string,
    unit: LearningUnit,
    questions?: readonly BankQuestion[],
  ) {
    if (questions) {
      for (const q of questions)
        await this
          .sql`insert into app.learning_bank_exposures(attempt_id,local_question_id,user_id,question_id,version)
        values(${attemptId},${q.id},${this.userId},${q.id},${q.version}) on conflict do nothing`;
    } else {
      await this
        .sql`insert into app.learning_bank_exposures(attempt_id,local_question_id,user_id,question_id,version)
        select ${attemptId},s.local_question_id,${this.userId},s.question_id,1 from app.learning_bank_sources s
        where s.unit_id=${unit.id} and s.unit_version=${unit.version} on conflict do nothing`;
    }
  }

  async claim(attemptId: string, localQuestionId: string): Promise<boolean> {
    const [ref] = await this.sql<
      { question_id: string }[]
    >`select question_id from app.learning_bank_exposures where attempt_id=${attemptId} and local_question_id=${localQuestionId} and user_id=${this.userId}`;
    if (!ref) return true;
    const claimed = await this
      .sql`insert into app.learning_bank_mastery(user_id,question_id,first_attempt_id)
      values(${this.userId},${ref.question_id},${attemptId}) on conflict do nothing returning question_id`;
    return claimed.length > 0;
  }
}

export class LearningBankRepository {
  constructor(private readonly database: DatabaseResource) {}

  async setEnabled(enabled: boolean) {
    await this.database
      .sql`update app.learning_bank_control set enabled=${enabled} where id=true`;
  }

  async importCatalog(
    entries: readonly {
      question: BankQuestion;
      unitId: string;
      unitVersion: number;
      localQuestionId: string;
    }[],
    blueprints: readonly BankBlueprint[],
    revisions: readonly BankCatalogRevision[] = [],
  ) {
    const updates = revisions.map((r) => bankCatalogRevisionSchema.parse(r));
    if (new Set(updates.map((r) => r.question.id)).size !== updates.length)
      conflict("公共题库目录含重复修订身份。");
    await this.database.sql.begin(async (sql) => {
      // 发布遇到锁竞争或异常慢语句时退出，避免维护事务长期占住业务资源。
      await sql`set local lock_timeout = '5s'`;
      await sql`set local statement_timeout = '30s'`;
      await sql`set local idle_in_transaction_session_timeout = '30s'`;
      await sql`select pg_advisory_xact_lock(hashtextextended('learning-publication',0))`;
      // 固定锁顺序；旧题修订、新题及蓝图全部提交或全部回滚。
      for (const revision of [...updates].sort((a, b) =>
        a.question.id.localeCompare(b.question.id),
      )) {
        const [current] = await sql<{ content_hash: string; published: boolean }[]>`
          select v.content_hash,q.published from app.learning_bank_questions q
          join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version
          where q.id=${revision.question.id} for update of q`;
        if (
          current?.content_hash === contentHash(revision.question) &&
          current.published
        )
          continue;
        await this.saveInTransaction(
          sql,
          revision.question.id,
          revision.expectedHash,
          revision.question,
          true,
          "目录逐题修订发布",
        );
      }
      for (const entry of entries) {
        const q = bankQuestionSchema.parse(entry.question);
        const [source] = await sql<
          { payload: LearningUnit }[]
        >`select payload from app.learning_unit_versions where unit_id=${entry.unitId} and version=${entry.unitVersion}`;
        if (
          !source ||
          contentHash(
            unitSchema
              .parse(source.payload)
              .questions.find((item) => item.id === entry.localQuestionId),
          ) !== contentHash(q.question)
        )
          conflict("题库来源必须与已发布单元的原题完全一致。");
        const [existing] = await sql<
          { content_hash: string }[]
        >`select content_hash from app.learning_bank_versions where question_id=${q.id} and version=1`;
        if (existing && existing.content_hash !== contentHash(q))
          conflict("题库初始版本已存在不同内容，请通过修订发布。");
        await sql`insert into app.learning_bank_questions(id,current_version,published,material_hash) values(${q.id},1,true,${bankIdentity(q.question)}) on conflict do nothing`;
        await sql`insert into app.learning_bank_versions(question_id,version,payload,content_hash,operator) values(${q.id},1,${JSON.stringify(q)}::jsonb,${contentHash(q)},'目录逐题自审导入') on conflict do nothing`;
        await sql`insert into app.learning_bank_sources(unit_id,unit_version,local_question_id,question_id) values(${entry.unitId},${entry.unitVersion},${entry.localQuestionId},${q.id}) on conflict do nothing`;
      }
      for (const value of blueprints) {
        const b = bankBlueprintSchema.parse(value);
        await sql`insert into app.learning_bank_blueprints(id,payload) values(${b.id},${JSON.stringify(b)}::jsonb) on conflict do nothing`;
      }
      await sql`update app.learning_bank_control set enabled=true where id=true`;
      // 保留现有成绩，只登记既有题目身份；不会补发或扣除分数。
      await sql`insert into app.learning_bank_exposures(attempt_id,local_question_id,user_id,question_id,version)
        select a.id,s.local_question_id,a.user_id,s.question_id,1 from app.learning_attempts a join app.learning_bank_sources s on s.unit_id=a.unit_id and s.unit_version=a.unit_version on conflict do nothing`;
      await sql`insert into app.learning_bank_mastery(user_id,question_id,first_attempt_id)
        select distinct on (r.user_id,e.question_id) r.user_id,e.question_id,r.attempt_id from app.learning_rewards r join app.learning_bank_exposures e on e.attempt_id=r.attempt_id and e.local_question_id=r.question_id
        order by r.user_id,e.question_id,r.created_at on conflict do nothing`;
    });
  }

  async list(filter: {
    level?: LearningLevel | undefined;
    topic?: string | undefined;
    goal?: string | undefined;
    type?: string | undefined;
    published?: boolean | undefined;
    offset: number;
    limit: number;
  }) {
    const rows = await this.database
      .sql`select q.id,q.current_version,q.published,v.content_hash,v.payload,count(*) over()::int as total
      from app.learning_bank_questions q join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version
      where (${filter.level ?? null}::text is null or v.payload->>'level'=${filter.level ?? null})
      and (${filter.topic ?? null}::text is null or v.payload->>'topic'=${filter.topic ?? null})
      and (${filter.goal ?? null}::text is null or v.payload->'question'->>'goalId'=${filter.goal ?? null})
      and (${filter.type ?? null}::text is null or v.payload->'question'->>'type'=${filter.type ?? null})
      and (${filter.published ?? null}::boolean is null or q.published=${filter.published ?? null})
      order by q.id limit ${filter.limit} offset ${filter.offset}`;
    return {
      items: rows.map((row) => {
        const item = { ...row };
        delete item.total;
        return item;
      }),
      total: Number(rows[0]?.total ?? 0),
    };
  }
  async detail(id: string) {
    const [row] = await this.database.sql<
      { published: boolean; payload: BankQuestion; content_hash: string }[]
    >`select q.published,v.payload,v.content_hash from app.learning_bank_questions q join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version where q.id=${id}`;
    if (!row)
      throw new AppError({
        code: "LEARNING_BANK_NOT_FOUND",
        message: "找不到这道题。",
        statusCode: 404,
      });
    const audit = await this.database
      .sql`select version,operation,operator,notes,created_at from app.learning_bank_audit where question_id=${id} order by id desc limit 50`;
    return { ...row, audit };
  }
  async save(
    id: string,
    expectedHash: string,
    value: BankQuestion,
    published: boolean,
    operator: string,
  ) {
    const q = bankQuestionSchema.parse(value);
    if (q.id !== id) conflict("修订不能更换题目身份。");
    return this.database.sql.begin((sql) =>
      this.saveInTransaction(sql, id, expectedHash, q, published, operator),
    );
  }
  private async saveInTransaction(
    sql: TransactionSql,
    id: string,
    expectedHash: string,
    q: BankQuestion,
    published: boolean,
    operator: string,
  ) {
    if (published && !availableForNewLearning(q.question, q.level))
      conflict(
        "此题型已停用或题面语言不合适，请使用符合年级和任务要求的英文题干与选项。",
      );
    const [current] = await sql<
      { payload: BankQuestion; content_hash: string }[]
    >`select v.payload,v.content_hash from app.learning_bank_questions q join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version where q.id=${id} for update of q`;
    if (current?.content_hash !== expectedHash)
      conflict("题目已更新，请重新读取后再保存。");
    const old = bankQuestionSchema.parse(current.payload);
    if (q.version !== old.version + 1) conflict("新版本必须递增。");
    validateRevision(old, q);
    const [duplicate] =
      await sql`select id from app.learning_bank_questions where material_hash=${bankIdentity(q.question)} and id<>${q.id}`;
    if (duplicate) conflict("同一道题已经存在，请修订原题，不要以新身份重复发布。");
    await sql`insert into app.learning_bank_versions(question_id,version,payload,content_hash,operator) values(${id},${q.version},${JSON.stringify(q)}::jsonb,${contentHash(q)},${operator})`;
    await sql`update app.learning_bank_questions set current_version=${q.version},published=${published},material_hash=${bankIdentity(q.question)},updated_at=now() where id=${id}`;
    await sql`insert into app.learning_bank_audit(question_id,version,operation,operator,notes) values(${id},${q.version},${published ? "publish" : "withdraw"},${operator},${q.reviewNotes})`;
    return { id, version: q.version, published };
  }
  async createVariant(
    templateId: string,
    expectedHash: string,
    value: BankQuestion,
    operator: string,
  ) {
    const q = bankQuestionSchema.parse({
      ...value,
      id: bankIdentity(value.question),
      version: 1,
    });
    if (!availableForNewLearning(q.question, q.level))
      conflict(
        "此题型已停用或题面语言不合适，请使用符合年级和任务要求的英文题干与选项。",
      );
    return this.database.sql.begin(async (sql) => {
      const [template] = await sql<
        { payload: BankQuestion; content_hash: string }[]
      >`select v.payload,v.content_hash from app.learning_bank_questions q join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version where q.id=${templateId} for share of q`;
      if (template?.content_hash !== expectedHash)
        conflict("参考题已更新，请重新打开后再新增。");
      validateRevision(bankQuestionSchema.parse(template.payload), q);
      const inserted =
        await sql`insert into app.learning_bank_questions(id,current_version,published,material_hash) values(${q.id},1,true,${bankIdentity(q.question)}) on conflict do nothing returning id`;
      if (!inserted.length)
        conflict("相同材料已在题库中，请修订原题；新题需要不同的题目材料。");
      await sql`insert into app.learning_bank_versions(question_id,version,payload,content_hash,operator) values(${q.id},1,${JSON.stringify(q)}::jsonb,${contentHash(q)},${operator})`;
      await sql`insert into app.learning_bank_audit(question_id,version,operation,operator,notes) values(${q.id},1,'create',${operator},${q.reviewNotes})`;
      return { id: q.id, version: 1, published: true };
    });
  }
  async preview(id: string, roleKey: string) {
    return this.database.sql.begin(async (sql) => {
      const [row] = await sql<
        { payload: BankBlueprint }[]
      >`select payload from app.learning_bank_blueprints where id=${id} and published`;
      if (!row) conflict("找不到组卷规则。");
      const blueprint = bankBlueprintSchema.parse(row.payload);
      const rows = await sql<
        { payload: BankQuestion }[]
      >`select v.payload from app.learning_bank_questions q join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version where q.published and v.payload->>'level'=${blueprint.level}`;
      const questions = assembleBankQuestions(
        blueprint,
        rows.map((r) => ({
          ...bankQuestionSchema.parse(r.payload),
          seen: false,
          mastered: false,
        })),
        roleKey,
        new Set(blueprint.prerequisiteGoalIds),
      );
      return {
        blueprint,
        unit: questions
          ? bankUnit(blueprint, questions, "preview.bank", roleKey, "同行者")
          : null,
        missing: questions === null,
      };
    });
  }
  async coverage() {
    const [rows, blueprints] = await Promise.all([
      this.database
        .sql`select v.payload->>'level' as level,v.payload->'question'->>'goalId' as goal,v.payload->'question'->>'type' as type,count(*)::int as questions from app.learning_bank_questions q join app.learning_bank_versions v on v.question_id=q.id and v.version=q.current_version where q.published group by 1,2,3 order by 1,2,3`,
      this.database
        .sql`select id,payload from app.learning_bank_blueprints where published order by id`,
    ]);
    return { goals: rows, blueprints };
  }
}
