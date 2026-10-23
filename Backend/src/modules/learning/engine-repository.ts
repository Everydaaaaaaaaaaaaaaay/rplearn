import {
  gaokaoCatalog,
  gaokaoUnitIds,
  isAdmittedGaokaoUnit,
  isHighSchool,
} from "./gaokao-policy.js";
import { questionListeningScript } from "./listening-speech.js";
import { LearningBankSession } from "./bank-repository.js";
import { LearningDirectionSession } from "./direction-repository.js";
import { LearningPromotionSession } from "./promotion-repository.js";
import type { PromotionCourse } from "./promotion-content.js";
import type { LearningContextReader } from "./context.js";
import { randomUUID } from "node:crypto";
import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import {
  contentHash,
  publicUnit,
  questionImageIds,
  questionAudios,
  unitSchema,
  type LearningLevel,
  type LearningUnit,
} from "./content.js";
import { gradeAnswer, type LearningAnswer, type GradeResult } from "./grading.js";
import { countChatCharacters, learningPolicy, levelProgress } from "./policy.js";
import { learningAudioSchema, type LearningAudioAsset } from "./audio.js";

import { learningImageSchema, type LearningImageAsset } from "./images.js";

function reject(code: string, message: string, statusCode = 409): never {
  throw new AppError({ code, message, statusCode });
}
interface CharacterRow {
  character_id: string;
  role_key: string;
  cycle_id: string;
  characters: number;
  revision: number;
}
interface AttemptRow {
  id: string;
  character_id: string;
  cycle_id: string;
  unit_id: string;
  unit_version: number;
  level_key: LearningLevel;
  revision: number;
  started_at: Date | string;
  first_completed_at: Date | string | null;
  superseded_at: Date | string | null;
  payload: LearningUnit;
}
interface RoundRow {
  id: string;
  ordinal: number;
  question_ids: string[];
  completed_at: Date | null;
}

export class LearningEngineRepository {
  constructor(
    private readonly database: DatabaseResource,
    private readonly context?: LearningContextReader,
  ) {}

  /** 所有账号内写入同序串行；事务回滚时收据和奖励也一并回滚。 */
  async command<T>(
    userId: string,
    requestId: string,
    operation: string,
    input: unknown,
    execute: (session: LearningSession) => Promise<T>,
  ): Promise<T> {
    const hash = contentHash(input);
    const result = await this.database.sql.begin(async (sql) => {
      // Batch withdrawal takes the exclusive counterpart; no answer can race it.
      await sql`select pg_advisory_xact_lock_shared(hashtextextended('learning-publication',0))`;
      await sql`select pg_advisory_xact_lock(hashtextextended(${`learning:${userId}`}, 0))`;
      const [existing] = await sql<
        { operation: string; request_hash: string; response: T }[]
      >`
        select operation, request_hash, response from app.learning_receipts where user_id=${userId} and request_id=${requestId}`;
      if (existing) {
        if (existing.operation !== operation || existing.request_hash !== hash)
          reject("LEARNING_REQUEST_CONFLICT", "这个请求标识已用于其他操作。");
        return existing.response;
      }
      const response = await execute(new LearningSession(sql, userId, this.context));
      await sql`insert into app.learning_receipts(user_id, request_id, operation, request_hash, response)
        values(${userId}, ${requestId}, ${operation}, ${hash}, ${JSON.stringify(response)}::jsonb)`;
      return response;
    });
    return result as T;
  }

  /** 页面首次打开可建立角色状态，不制造随机请求收据。 */
  async inspect<T>(
    userId: string,
    query: (session: LearningSession) => Promise<T>,
  ): Promise<T> {
    const result = await this.database.sql.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(hashtextextended(${`learning:${userId}`}, 0))`;
      return query(new LearningSession(sql, userId, this.context));
    });
    return result as T;
  }

  async read<T>(
    userId: string,
    query: (session: LearningSession) => Promise<T>,
  ): Promise<T> {
    const result = await this.database.sql.begin(
      "isolation level repeatable read read only",
      (sql) => query(new LearningSession(sql, userId, this.context)),
    );
    return result as T;
  }

  async publish(value: unknown): Promise<void> {
    await this.publishBatch([value]);
  }

  /** 完整目录共用一次事务；后面的版本冲突不能留下发布了一半的题库。 */
  async publishBatch(
    values: readonly unknown[],
    audioAssets?: readonly LearningAudioAsset[],
    imageAssets?: readonly LearningImageAsset[],
  ): Promise<void> {
    const units = values
      .map((value) => unitSchema.parse(value))
      .sort((a, b) => a.id.localeCompare(b.id));
    if (
      units.length === 0 ||
      new Set(units.map((unit) => unit.id)).size !== units.length
    )
      throw new Error("发布目录不能为空，也不能包含重复的单元标识。");
    await this.database.sql.begin(async (sql) => {
      // 发布遇到锁竞争或异常慢语句时退出，避免维护事务长期占住业务资源。
      await sql`set local lock_timeout = '5s'`;
      await sql`set local statement_timeout = '30s'`;
      await sql`set local idle_in_transaction_session_timeout = '30s'`;
      for (const value of [...(audioAssets ?? [])].sort((a, b) =>
        a.id.localeCompare(b.id),
      )) {
        const asset = learningAudioSchema.parse(value);
        await sql`select pg_advisory_xact_lock(hashtextextended(${`learning-audio:${asset.id}`}, 0))`;
        const [existing] = await sql<
          { metadata: unknown }[]
        >`select metadata from app.learning_audio_assets where id=${asset.id}`;
        if (existing && contentHash(existing.metadata) !== contentHash(asset))
          reject("LEARNING_IMMUTABLE_AUDIO", "已发布音频的内容与审核信息不可改写。");
        await sql`insert into app.learning_audio_assets(id,sha256,metadata) values(${asset.id},${asset.sha256},${JSON.stringify(asset)}::jsonb) on conflict do nothing`;
      }
      for (const value of [...(imageAssets ?? [])].sort((a, b) =>
        a.id.localeCompare(b.id),
      )) {
        const asset = learningImageSchema.parse(value);
        await sql`select pg_advisory_xact_lock(hashtextextended(${`learning-image:${asset.id}`}, 0))`;
        const [existing] = await sql<
          { metadata: unknown }[]
        >`select metadata from app.learning_image_assets where id=${asset.id}`;
        if (existing && contentHash(existing.metadata) !== contentHash(asset))
          reject("LEARNING_IMMUTABLE_IMAGE", "已发布图片的内容与审核信息不可改写。");
        await sql`insert into app.learning_image_assets(id,sha256,metadata) values(${asset.id},${asset.sha256},${JSON.stringify(asset)}::jsonb) on conflict do nothing`;
      }
      if (audioAssets !== undefined) {
        for (const unit of units)
          for (const audio of unit.questions.flatMap(questionAudios)) {
            const [row] = await sql<
              { metadata: unknown }[]
            >`select metadata from app.learning_audio_assets where id=${audio.assetId}`;
            const asset = row ? learningAudioSchema.parse(row.metadata) : undefined;
            if (asset?.transcript !== audio.text || asset.voice !== audio.voice)
              reject(
                "LEARNING_AUDIO_NOT_READY",
                "听力原文、声音与已审核资源不一致，不能发布。",
              );
          }
      }
      for (const unit of units) await this.publishInTransaction(sql, unit);
    });
  }

  /** 仅供学习模块仓库在持有发布事务时调用。 */
  async publishInTransaction(sql: TransactionSql, unit: LearningUnit): Promise<void> {
    await sql`select pg_advisory_xact_lock(hashtextextended('learning-publication',0))`;
    // 所有发布入口（包括后台审核与生成库）都必须验证资源归档，不能绕过目录发布器。
    for (const imageId of new Set(unit.questions.flatMap(questionImageIds))) {
      const [asset] =
        await sql`select id from app.learning_image_assets where id=${imageId}`;
      if (!asset) reject("LEARNING_IMAGE_NOT_READY", "图片未完成审核归档，不能发布。");
    }
    const hash = contentHash(unit);
    await sql`select pg_advisory_xact_lock(hashtextextended(${`learning-unit:${unit.id}`}, 0))`;
    const [identity] = await sql<
      { role_key: string; level_key: string; current_version: number }[]
    >`
        select role_key, level_key, current_version from app.learning_units where id=${unit.id}`;
    if (
      identity &&
      (identity.role_key !== unit.roleKey || identity.level_key !== unit.level)
    )
      reject("LEARNING_UNIT_IDENTITY_CONFLICT", "单元标识不能换成另一角色或水平。");
    const [oldVersion] = await sql<
      { content_hash: string }[]
    >`select content_hash from app.learning_unit_versions where unit_id=${unit.id} and version=${unit.version}`;
    if (oldVersion) {
      if (oldVersion.content_hash !== hash)
        reject("LEARNING_IMMUTABLE_CONTENT", "已发布版本不可改写，请创建新版本。");
      return;
    }
    if (identity && unit.version <= identity.current_version)
      reject("LEARNING_VERSION_ORDER", "新版本必须大于已发布版本。");
    await sql`insert into app.learning_units(id, role_key, level_key, current_version, published)
        values(${unit.id}, ${unit.roleKey}, ${unit.level}, ${unit.version}, true)
        on conflict(id) do update set current_version=excluded.current_version, published=true`;
    await sql`insert into app.learning_unit_versions(unit_id, version, payload, content_hash)
        values(${unit.id}, ${unit.version}, ${JSON.stringify(unit)}::jsonb, ${hash})`;
  }
}

/** 仅在仓库拥有的事务中使用；可信消息入口由服务层组装，不公开字数写接口。 */
export class LearningSession {
  constructor(
    private readonly sql: TransactionSql,
    private readonly userId: string,
    private readonly context?: LearningContextReader,
  ) {}

  directions() {
    return new LearningDirectionSession(this.sql, this.userId);
  }

  async listeningScript(attemptId: string, questionId: string, assetId: string) {
    const attempt = await this.rawAttempt(attemptId);
    const question = unitSchema
      .parse(attempt.payload)
      .questions.find((q) => q.id === questionId);
    const script = question && (await questionListeningScript(question, assetId));
    if (!script)
      reject("LEARNING_AUDIO_NOT_FOUND", "这道题没有可播放的听力素材。", 404);
    return script;
  }

  async audioAsset(
    attemptId: string,
    questionId: string,
    assetId?: string,
  ): Promise<LearningAudioAsset> {
    const attempt = await this.rawAttempt(attemptId);
    const question = unitSchema
      .parse(attempt.payload)
      .questions.find((q) => q.id === questionId);
    const audios = question ? questionAudios(question) : [];
    const audio = assetId
      ? audios.find((item) => item.assetId === assetId)
      : audios.length === 1
        ? audios[0]
        : undefined;
    if (!audio) reject("LEARNING_AUDIO_NOT_FOUND", "这道题没有可播放的听力素材。", 404);
    const [row] = await this.sql<
      { metadata: unknown }[]
    >`select metadata from app.learning_audio_assets where id=${audio.assetId}`;
    if (!row)
      reject("LEARNING_AUDIO_NOT_READY", "听力素材暂不可用，请重试或稍后补答。", 503);
    return learningAudioSchema.parse(row.metadata);
  }

  async imageAsset(
    attemptId: string,
    questionId: string,
    assetId: string,
  ): Promise<LearningImageAsset> {
    const attempt = await this.rawAttempt(attemptId);
    const question = unitSchema
      .parse(attempt.payload)
      .questions.find((q) => q.id === questionId);
    if (!question || !questionImageIds(question).includes(assetId))
      reject("LEARNING_IMAGE_NOT_FOUND", "这道题没有对应的图片素材。", 404);
    const [row] = await this.sql<
      { metadata: unknown }[]
    >`select metadata from app.learning_image_assets where id=${assetId}`;
    if (!row)
      reject("LEARNING_IMAGE_NOT_READY", "图片素材暂不可用，请重试或稍后补答。", 503);
    return learningImageSchema.parse(row.metadata);
  }

  promotions(courses: readonly PromotionCourse[]) {
    return new LearningPromotionSession(this.sql, this.userId, this.context, courses);
  }

  async currentLevel() {
    if (!this.context) throw new Error("未配置学习档案读取服务。");
    return this.context.profile(this.sql, this.userId);
  }

  async resolveCharacter(characterId: string) {
    if (!this.context) throw new Error("未配置学习角色读取服务。");
    const role = await this.context.character(this.sql, this.userId, characterId);
    return this.ensureCharacter(characterId, role);
  }

  async assertRevision(id: string, expectedRevision: number) {
    const attempt = await this.rawAttempt(id);
    if (attempt.revision !== expectedRevision)
      reject("LEARNING_REVISION_CONFLICT", "挑战已在其他设备更新，请刷新后继续。");
  }

  async availability(
    roleKey: string,
    level: LearningLevel,
    characterId: string,
    completeGroups = false,
  ) {
    const { selectedDirection } = await this.directions().read();
    // 备考稿尚未通过正式发布门槛，不回退到同一用户的普通年级题库。
    if (selectedDirection !== "general")
      return { availableUnits: 0, generationStatus: null };
    if (isHighSchool(level))
      return {
        availableUnits: completeGroups
          ? (await this.gaokaoCandidates(level)).length
          : 0,
        generationStatus: null,
      };
    const [row] = await this.sql<
      { count: number }[]
    >`select count(*)::integer as count from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version
      where u.published and u.level_key=${level}
        and not exists (select 1 from jsonb_array_elements(v.payload->'questions') q where q->>'type'='dictation')
        and (v.payload ? 'originalGroup' or u.level_key not in ('senior1','senior2','senior3','undergraduate','postgraduate','advanced')
          or not exists (select 1 from jsonb_array_elements(v.payload->'questions') q
            where q->>'type'='listeningChoice' and ((q->>'prompt') ~ '[一-鿿]' or (q->'options')::text ~ '[一-鿿]')))
      and ((u.role_key=${roleKey} and not (v.payload ? 'originalGroup')) or (${completeGroups} and v.payload ? 'originalGroup'))
      and not exists(select 1 from app.learning_attempts a where a.user_id=${this.userId} and (a.character_id=${characterId} or v.payload ? 'originalGroup') and a.unit_id=u.id)
        and not exists(select 1 from app.learning_bank_sources s join app.learning_bank_exposures e on e.question_id=s.question_id
          where s.unit_id=u.id and s.unit_version=u.current_version and e.user_id=${this.userId})
        and not exists(select 1 from app.learning_bank_sources s join app.learning_bank_questions b on b.id=s.question_id
          where s.unit_id=u.id and s.unit_version=u.current_version and (not b.published or b.current_version<>1))`;
    const [job] = await this.sql<
      { status: string }[]
    >`select status from app.learning_generation_jobs
      where role_key=${roleKey} and level_key=${level} and status in ('pending','running','review') limit 1`;
    const sharedCount = (
      await new LearningBankSession(this.sql, this.userId).choices(level, roleKey)
    ).length;
    return {
      availableUnits: (row?.count ?? 0) + sharedCount,
      generationStatus:
        (row?.count ?? 0) + sharedCount === 0 ? (job?.status ?? null) : null,
    };
  }

  async history(
    characterId: string,
    limit: number,
    cursor?: { startedAt: string; id: string },
  ) {
    const rows = await this.sql<
      {
        id: string;
        level_key: LearningLevel;
        started_at: string;
        first_completed_at: string | null;
        title: string;
        question_count: number;
        correct_count: number;
      }[]
    >`
      select a.id,a.level_key,a.started_at::text,a.first_completed_at::text,coalesce(a.snapshot,v.payload)->>'title' as title,
        jsonb_array_length(coalesce(a.snapshot,v.payload)->'questions') as question_count,
        (select count(*)::integer from app.learning_rewards r where r.attempt_id=a.id) as correct_count
      from app.learning_attempts a left join app.learning_unit_versions v on v.unit_id=a.unit_id and v.version=a.unit_version
      where a.user_id=${this.userId} and a.character_id=${characterId}
        and (${cursor === undefined} or (a.started_at,a.id)<(${cursor?.startedAt ?? "9999-01-01T00:00:00Z"}::timestamptz,${cursor?.id ?? "ffffffff-ffff-ffff-ffff-ffffffffffff"}::uuid))
      order by a.started_at desc,a.id desc limit ${limit + 1}`;
    const items = rows.slice(0, limit).map((row) => ({
      id: row.id,
      title: row.title,
      level: row.level_key,
      direction: "general" as const,
      startedAt: new Date(row.started_at).toISOString(),
      firstCompletedAt:
        row.first_completed_at === null
          ? null
          : new Date(row.first_completed_at).toISOString(),
      correctCount: row.correct_count,
      questionCount: row.question_count,
    }));
    const last = rows[limit - 1];
    return {
      items,
      next:
        rows.length > limit && last
          ? { startedAt: last.started_at, id: last.id }
          : null,
    };
  }

  /** 只调整当前聊天循环，不伪造消息、答题成绩或学习星星。 */
  async debugFill(characterId: string, cycleId: string) {
    const state = await this.character(characterId);
    if (state.cycleId !== cycleId)
      reject("LEARNING_CYCLE_CHANGED", "挑战循环已变化，请刷新后重试。");
    if (state.activeAttemptId) reject("LEARNING_ATTEMPT_ACTIVE", "请先完成当前挑战。");
    await this
      .sql`update app.learning_characters set characters=${learningPolicy.characterThreshold},revision=revision+1
      where user_id=${this.userId} and character_id=${characterId} and characters<${learningPolicy.characterThreshold}`;
    return this.character(characterId);
  }

  async ensureCharacter(characterId: string, roleKey: string) {
    await this
      .sql`insert into app.learning_characters(user_id, character_id, role_key, cycle_id)
      values(${this.userId},${characterId},${roleKey},${randomUUID()}) on conflict(user_id, character_id) do nothing`;
    const state = await this.character(characterId);
    if (state.roleKey !== roleKey)
      reject("LEARNING_CHARACTER_CONFLICT", "角色学习身份不一致。");
    return state;
  }

  async character(characterId: string) {
    const [row] = await this.sql<
      CharacterRow[]
    >`select character_id,role_key,cycle_id,characters,revision
      from app.learning_characters where user_id=${this.userId} and character_id=${characterId}`;
    if (!row) reject("LEARNING_CHARACTER_NOT_FOUND", "找不到这个角色的学习记录。", 404);
    const [active] = await this.sql<
      { id: string }[]
    >`select a.id from app.learning_attempts a
      left join app.learning_unit_versions v on v.unit_id=a.unit_id and v.version=a.unit_version
      where a.user_id=${this.userId} and a.character_id=${characterId} and a.first_completed_at is null and a.superseded_at is null
        and (a.level_key not in ('senior1','senior2','senior3')
          or (a.unit_id=any(${gaokaoUnitIds()}) and a.snapshot is null
            and v.content_hash=any(${gaokaoCatalog().practices.map((p) => p.contentHash)})))`;
    return {
      characterId: row.character_id,
      roleKey: row.role_key,
      cycleId: row.cycle_id,
      // A lower threshold makes existing progress ready without rewriting it.
      characters: Math.min(row.characters, learningPolicy.characterThreshold),
      threshold: learningPolicy.characterThreshold,
      revision: row.revision,
      activeAttemptId: active?.id ?? null,
    };
  }

  async recordMessage(input: {
    characterId: string;
    cycleId: string;
    messageId: string;
    text: string;
  }) {
    const state = await this.character(input.characterId);
    const count = countChatCharacters(input.text);
    const accepted =
      state.cycleId === input.cycleId &&
      state.activeAttemptId === null &&
      state.characters < learningPolicy.characterThreshold;
    const inserted = await this
      .sql`insert into app.learning_message_events(user_id,message_id,character_id,cycle_id,character_count,accepted)
      values(${this.userId},${input.messageId},${input.characterId},${input.cycleId},${count},${accepted})
      on conflict(user_id,message_id) do nothing returning message_id`;
    if (inserted.length > 0 && accepted && count > 0) {
      await this
        .sql`update app.learning_characters set characters=least(${learningPolicy.characterThreshold}, characters+${count}), revision=revision+1
        where user_id=${this.userId} and character_id=${input.characterId}`;
    }
    return this.character(input.characterId);
  }

  async originals(level: LearningLevel) {
    if (isHighSchool(level)) {
      const rows = await this.sql<{ payload: LearningUnit }[]>`
        select v.payload from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version
        where u.published and u.level_key=${level} and u.id=any(${gaokaoUnitIds()}) order by u.id`;
      return {
        units: rows
          .filter((r) => isAdmittedGaokaoUnit(r.payload))
          .map(({ payload: u }) => ({
            id: u.id,
            title: u.title,
            family: u.originalGroup?.family ?? "reading_choice",
            label: u.originalGroup?.label ?? "高考真题",
            questions: u.questions.length,
          })),
      };
    }
    const rows = await this.sql<
      { id: string; title: string; family: string; label: string; questions: number }[]
    >`
      select u.id,v.payload->>'title' as title,v.payload->'originalGroup'->>'family' as family,
      v.payload->'originalGroup'->>'label' as label,jsonb_array_length(v.payload->'questions') as questions
      from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version
      where u.published and u.level_key=${level} and v.payload ? 'originalGroup' order by family,u.id`;
    return { units: rows };
  }

  private async gaokaoCandidates(level: LearningLevel, originalUnitId?: string) {
    const ids = gaokaoUnitIds();
    const rows = await this.sql<{ payload: LearningUnit }[]>`
      select v.payload from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version
      where u.published and u.level_key=${level} and u.id=any(${ids})
        and (${originalUnitId ?? null}::text is null or u.id=${originalUnitId ?? null})
        and not exists (
          select 1 from app.learning_attempts a left join app.learning_unit_versions av on av.unit_id=a.unit_id and av.version=a.unit_version
          where a.user_id=${this.userId} and (
            (a.unit_id=any(${ids}) and (coalesce(a.snapshot,av.payload)->'originalGroup'->'sourceGroupIds') ?|
              array(select jsonb_array_elements_text(v.payload->'originalGroup'->'sourceGroupIds')))
            or a.unit_id=any(array(select split_part(jsonb_array_elements_text(v.payload->'originalGroup'->'sourceGroupIds'),'#',1)))))
      order by random()`;
    return rows.filter((r) => isAdmittedGaokaoUnit(r.payload));
  }

  /** Withdraw only obsolete active senior drills. Never rewrite answers, points or frozen payloads. */
  private async supersedeObsoleteHighSchool(characterId: string) {
    const rows = await this.sql<AttemptRow[]>`
      select a.*,coalesce(a.snapshot,v.payload) as payload from app.learning_attempts a
      left join app.learning_unit_versions v on v.unit_id=a.unit_id and v.version=a.unit_version
      where a.user_id=${this.userId} and a.character_id=${characterId}
        and a.level_key in ('senior1','senior2','senior3') and a.first_completed_at is null and a.superseded_at is null`;
    for (const a of rows)
      if (!isAdmittedGaokaoUnit(a.payload)) {
        await this
          .sql`update app.learning_attempts set superseded_at=now(),revision=revision+1 where id=${a.id}`;
        await this
          .sql`update app.learning_characters set cycle_id=${randomUUID()},revision=revision+1
        where user_id=${this.userId} and character_id=${characterId} and cycle_id=${a.cycle_id}`;
      }
  }

  async start(
    characterId: string,
    level: LearningLevel,
    options: { completeGroups?: boolean; originalUnitId?: string } = {},
  ) {
    await this
      .sql`select pg_advisory_xact_lock_shared(hashtextextended('learning-publication',0))`;
    await this.supersedeObsoleteHighSchool(characterId);
    const state = await this.character(characterId);
    if (isHighSchool(level) && !options.completeGroups)
      reject("LEARNING_CLIENT_UPDATE_REQUIRED", "高中高考完整题组需要新版 App。", 426);
    if (options.originalUnitId && !options.completeGroups)
      reject("LEARNING_CLIENT_UPDATE_REQUIRED", "完整题组需要新版 App。", 426);
    if (state.activeAttemptId && !options.completeGroups) {
      const active = await this.rawAttempt(state.activeAttemptId);
      if (active.payload.originalGroup)
        reject(
          "LEARNING_CLIENT_UPDATE_REQUIRED",
          "这次完整题组需要新版 App，请更新后继续。",
          426,
        );
    }
    if (state.activeAttemptId)
      return {
        status: "started" as const,
        attempt: await this.attempt(state.activeAttemptId),
      };
    const { selectedDirection } = await this.directions().read();
    if (selectedDirection !== "general")
      reject(
        "LEARNING_DIRECTION_NOT_READY",
        "这个备考方向的题目仍在审核中，暂时无法开启挑战。",
      );
    if (state.characters < learningPolicy.characterThreshold)
      reject("LEARNING_NOT_READY", "再聊一会儿，进度满后就能开启挑战。");
    const [dedicated] = isHighSchool(level)
      ? await this.gaokaoCandidates(level, options.originalUnitId)
      : await this.sql<{ payload: LearningUnit }[]>`
      select v.payload from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version
      where u.published and u.level_key=${level}
        and not exists (select 1 from jsonb_array_elements(v.payload->'questions') q where q->>'type'='dictation')
        and (v.payload ? 'originalGroup' or u.level_key not in ('senior1','senior2','senior3','undergraduate','postgraduate','advanced')
          or not exists (select 1 from jsonb_array_elements(v.payload->'questions') q
            where q->>'type'='listeningChoice' and ((q->>'prompt') ~ '[一-鿿]' or (q->'options')::text ~ '[一-鿿]')))
        and ((u.role_key=${state.roleKey} and not (v.payload ? 'originalGroup'))
          or (${options.completeGroups === true} and v.payload ? 'originalGroup'))
        and (${options.originalUnitId ?? null}::text is null or u.id=${options.originalUnitId ?? null})
        and not exists(select 1 from app.learning_attempts a where a.user_id=${this.userId} and (a.character_id=${characterId} or v.payload ? 'originalGroup') and a.unit_id=u.id)
        and not exists(select 1 from app.learning_bank_sources s join app.learning_bank_exposures e on e.question_id=s.question_id
          where s.unit_id=u.id and s.unit_version=u.current_version and e.user_id=${this.userId})
        and not exists(select 1 from app.learning_bank_sources s join app.learning_bank_questions b on b.id=s.question_id
          where s.unit_id=u.id and s.unit_version=u.current_version and (not b.published or b.current_version<>1))
      order by (v.payload ? 'originalGroup') desc,random() limit 1`;
    const attemptId = randomUUID();
    const bank = new LearningBankSession(this.sql, this.userId);
    const companion = await this.context?.companion?.(
      this.sql,
      this.userId,
      characterId,
    );
    // 已有更完整的新练习时，不让早期短专属单元遮住公共长单元；纯复习不抢占未见专属题。
    const composed =
      isHighSchool(level) || dedicated?.payload.originalGroup || options.originalUnitId
        ? null
        : await bank.compose(
            level,
            state.roleKey,
            companion?.name ?? "同行者",
            attemptId,
            dedicated
              ? {
                  minQuestions: dedicated.payload.questions.length + 1,
                  excludeReviewOnly: true,
                }
              : {},
          );
    const candidate = composed ? undefined : dedicated;
    if (!candidate && !composed) {
      // 只为确有角色蓝图的主角色保留原生成队列；普通角色缺题由公共题库补齐。
      if (
        !options.originalUnitId &&
        ["oliver", "ruby", "marcus"].includes(state.roleKey) &&
        ["primary3", "primary4"].includes(level)
      ) {
        await this.sql`insert into app.learning_generation_jobs(id, role_key, level_key)
          values(${randomUUID()},${state.roleKey},${level}) on conflict do nothing`;
      }
      return { status: "preparing" as const, attempt: null };
    }
    const unit = unitSchema.parse(candidate?.payload ?? composed?.unit);
    await this
      .sql`insert into app.learning_attempts(id,user_id,character_id,cycle_id,unit_id,unit_version,level_key,snapshot,blueprint_id)
      values(${attemptId},${this.userId},${characterId},${state.cycleId},${candidate ? unit.id : null},${candidate ? unit.version : null},${level},${composed ? JSON.stringify(unit) : null}::jsonb,${composed?.blueprintId ?? null})`;
    await bank.recordExposure(attemptId, unit, composed?.questions);
    await this.sql`insert into app.learning_rounds(id,attempt_id,ordinal,question_ids)
      values(${randomUUID()},${attemptId},0,${unit.questions.map((q) => q.id)})`;
    await this
      .sql`update app.learning_characters set revision=revision+1 where user_id=${this.userId} and character_id=${characterId}`;
    return { status: "started" as const, attempt: await this.attempt(attemptId) };
  }

  private async rawAttempt(id: string): Promise<AttemptRow> {
    const [row] = await this.sql<
      AttemptRow[]
    >`select a.*, coalesce(a.snapshot,v.payload) as payload from app.learning_attempts a
      left join app.learning_unit_versions v on v.unit_id=a.unit_id and v.version=a.unit_version
      where a.id=${id} and a.user_id=${this.userId}`;
    if (!row) reject("LEARNING_ATTEMPT_NOT_FOUND", "找不到这次挑战。", 404);
    return row;
  }

  async attempt(id: string) {
    const row = await this.rawAttempt(id);
    const [round] = await this.sql<
      RoundRow[]
    >`select id,ordinal,question_ids,completed_at from app.learning_rounds
      where attempt_id=${id} order by ordinal desc limit 1`;
    if (!round) throw new Error("挑战缺少作答轮次。");
    const answers = await this.sql<
      { question_id: string; answer: LearningAnswer; result: GradeResult }[]
    >`
      select question_id,answer,result from app.learning_answers where round_id=${round.id} order by created_at,question_id`;
    const rewarded = await this.sql<
      { question_id: string }[]
    >`select question_id from app.learning_rewards where attempt_id=${id}`;
    return {
      id,
      characterId: row.character_id,
      level: row.level_key,
      direction: "general" as const,
      revision: row.revision,
      startedAt: new Date(row.started_at).toISOString(),
      firstCompletedAt:
        row.first_completed_at === null
          ? null
          : new Date(row.first_completed_at).toISOString(),
      unit: publicUnit(unitSchema.parse(row.payload), row.id),
      correctQuestionIds: rewarded.map((r) => r.question_id),
      round: {
        id: round.id,
        ordinal: round.ordinal,
        questionIds: round.question_ids,
        completed: round.completed_at !== null,
        answers: answers.map((a) => ({
          questionId: a.question_id,
          answer: a.answer,
          result: a.result,
        })),
      },
    };
  }

  async submit(input: {
    attemptId: string;
    roundId: string;
    questionId: string;
    answer: LearningAnswer;
  }) {
    await this
      .sql`select pg_advisory_xact_lock_shared(hashtextextended('learning-publication',0))`;
    const attempt = await this.rawAttempt(input.attemptId);
    this.assertPracticeCurrent(attempt);
    const [round] = await this.sql<
      RoundRow[]
    >`select id,ordinal,question_ids,completed_at from app.learning_rounds
      where id=${input.roundId} and attempt_id=${input.attemptId}`;
    if (round?.completed_at !== null || !round.question_ids.includes(input.questionId))
      reject("LEARNING_ROUND_CONFLICT", "这道题已不在当前作答轮，请刷新挑战。");
    const [answered] = await this
      .sql`select question_id from app.learning_answers where round_id=${input.roundId} and question_id=${input.questionId}`;
    if (answered)
      reject("LEARNING_ALREADY_ANSWERED", "这一轮已经提交过这道题，请继续或稍后补答。");
    const unit = unitSchema.parse(attempt.payload);
    const question = unit.questions.find((q) => q.id === input.questionId);
    if (!question) reject("LEARNING_QUESTION_NOT_FOUND", "找不到这道题。", 404);
    const result = gradeAnswer(question, input.answer);
    await this.sql`insert into app.learning_answers(round_id,question_id,answer,result)
      values(${input.roundId},${input.questionId},${JSON.stringify(input.answer)}::jsonb,${JSON.stringify(result)}::jsonb)`;
    let awardedPoints = 0;
    if (result.outcome === "correct") {
      // 原创完整组跨旅伴只计一次；账号命令锁使查询与奖励写入串行。
      const priorOriginal = unit.originalGroup
        ? await this.sql`
        select 1 from app.learning_rewards r join app.learning_attempts a on a.id=r.attempt_id
        where r.user_id=${this.userId} and (a.unit_id=${unit.id} or (${isHighSchool(unit.level)} and a.unit_id=any(${gaokaoUnitIds()}))) and r.question_id=${input.questionId} and r.points>0 limit 1`
        : [];
      const firstMastery = unit.originalGroup
        ? priorOriginal.length === 0
        : await new LearningBankSession(this.sql, this.userId).claim(
            input.attemptId,
            input.questionId,
          );
      const award = await this
        .sql`insert into app.learning_rewards(attempt_id,question_id,user_id,level_key,goal_id,points)
        values(${input.attemptId},${input.questionId},${this.userId},${attempt.level_key},${question.goalId},${firstMastery ? 1 : 0})
        on conflict(attempt_id,question_id) do nothing returning points`;
      if (award.length > 0 && firstMastery) {
        awardedPoints = 1;
        const [progress] = await this.sql<
          { points: number }[]
        >`insert into app.learning_level_progress(user_id,level_key,points)
          values(${this.userId},${attempt.level_key},1) on conflict(user_id,level_key)
          do update set points=app.learning_level_progress.points+1 returning points`;
        if (!progress) throw new Error("学习进度写入失败。");
        for (let star = 1; star <= levelProgress(progress.points).stars; star++) {
          await this
            .sql`insert into app.learning_milestones(user_id,level_key,star) values(${this.userId},${attempt.level_key},${star}) on conflict do nothing`;
        }
      }
    }
    await this
      .sql`update app.learning_attempts set revision=revision+1 where id=${input.attemptId}`;
    // 补答轮自动收束；首轮等待用户确认，才能重置角色进度。
    if (round.ordinal > 0) {
      await this
        .sql`update app.learning_rounds set completed_at=now() where id=${input.roundId}
        and cardinality(question_ids)=(select count(*) from app.learning_answers where round_id=${input.roundId})`;
    }
    return {
      result,
      awardedPoints,
      attempt: await this.attempt(input.attemptId),
      progress: await this.progress(),
    };
  }

  private assertPracticeCurrent(attempt: AttemptRow) {
    if (
      attempt.superseded_at !== null ||
      (isHighSchool(attempt.level_key) && !isAdmittedGaokaoUnit(attempt.payload))
    )
      reject(
        "LEARNING_PRACTICE_REPLACED",
        "本练习已更新或撤回，原作答和积分已保留。请退出并开启新练习。",
      );
  }

  async finish(id: string, skipRemaining: boolean) {
    const attempt = await this.rawAttempt(id);
    this.assertPracticeCurrent(attempt);
    if (attempt.first_completed_at !== null) return this.attempt(id);
    const [round] = await this.sql<
      RoundRow[]
    >`select id,ordinal,question_ids,completed_at from app.learning_rounds where attempt_id=${id} and ordinal=0`;
    if (!round) throw new Error("首轮记录不存在。");
    const answered = await this.sql<
      { question_id: string }[]
    >`select question_id from app.learning_answers where round_id=${round.id}`;
    const remaining = round.question_ids.filter(
      (q) => !answered.some((a) => a.question_id === q),
    );
    if (remaining.length > 0 && !skipRemaining)
      reject(
        "LEARNING_ROUND_INCOMPLETE",
        "还有题目未完成，可以继续或明确跳过剩余题目。",
      );
    for (const questionId of remaining) {
      await this.submit({
        attemptId: id,
        roundId: round.id,
        questionId,
        answer: { kind: "skip" },
      });
    }
    await this
      .sql`update app.learning_rounds set completed_at=now() where id=${round.id}`;
    await this
      .sql`update app.learning_attempts set first_completed_at=now(),revision=revision+1 where id=${id}`;
    await this
      .sql`update app.learning_characters set cycle_id=${randomUUID()}, characters=0, revision=revision+1
      where user_id=${this.userId} and character_id=${attempt.character_id} and cycle_id=${attempt.cycle_id}`;
    return this.attempt(id);
  }

  async retry(id: string) {
    const attempt = await this.rawAttempt(id);
    this.assertPracticeCurrent(attempt);
    if (attempt.first_completed_at === null)
      reject("LEARNING_FIRST_ROUND_ACTIVE", "请先结束当前首轮挑战。");
    const [lastRound] = await this.sql<
      RoundRow[]
    >`select id,ordinal,question_ids,completed_at from app.learning_rounds where attempt_id=${id} order by ordinal desc limit 1`;
    if (!lastRound) throw new Error("找不到历史轮次。");
    if (lastRound.completed_at === null) return this.attempt(id);
    const rewarded = await this.sql<
      { question_id: string }[]
    >`select question_id from app.learning_rewards where attempt_id=${id}`;
    const remaining = unitSchema
      .parse(attempt.payload)
      .questions.map((q) => q.id)
      .filter((q) => !rewarded.some((r) => r.question_id === q));
    if (remaining.length === 0) return this.attempt(id);
    await this
      .sql`insert into app.learning_rounds(id,attempt_id,ordinal,question_ids) values(${randomUUID()},${id},${lastRound.ordinal + 1},${remaining})`;
    await this.sql`update app.learning_attempts set revision=revision+1 where id=${id}`;
    return this.attempt(id);
  }

  async publishedContent(completeGroups = false) {
    return this.sql<{ level: LearningLevel; count: number }[]>`
      select u.level_key as level,count(*)::integer as count from app.learning_units u
      join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version
      where u.published and (${completeGroups} or not (v.payload ? 'originalGroup'))
        and (u.level_key not in ('senior1','senior2','senior3') or
          (${completeGroups} and u.id=any(${gaokaoUnitIds()}) and v.content_hash=any(${gaokaoCatalog().practices.map((p) => p.contentHash)}))) group by u.level_key`;
  }

  async progress() {
    const rows = await this.sql<
      { level_key: LearningLevel; points: number }[]
    >`select level_key,points from app.learning_level_progress where user_id=${this.userId} order by level_key`;
    return rows.map((row) => ({ level: row.level_key, ...levelProgress(row.points) }));
  }
}
