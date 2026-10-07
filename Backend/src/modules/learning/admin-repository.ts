import { LearningBankRepository } from "./bank-repository.js";
import type { DatabaseResource } from "../../db/client.js";
import { questionImageIds, unitSchema, type LearningUnit } from "./content.js";
import { learningAudioSchema } from "./audio.js";
import { learningImageSchema } from "./images.js";

export type LearningAdminFilter = Readonly<{
  role?: string | undefined;
  level?: string | undefined;
  status?: string | undefined;
  offset: number;
  limit: number;
}>;
/** 后台只读取公开课程与生成记录，不读取用户聊天、作答或身份。 */
export class LearningAdminRepository {
  constructor(private readonly database: DatabaseResource) {}
  bank() {
    return new LearningBankRepository(this.database);
  }
  async media(unit: Pick<LearningUnit, "questions"> | null) {
    if (!unit) return { audio: [], images: [] };
    const imageIds = [...new Set(unit.questions.flatMap(questionImageIds))];
    const audioIds = [
      ...new Set(
        unit.questions.flatMap((question) =>
          "audio" in question ? [question.audio.assetId] : [],
        ),
      ),
    ];
    const [images, audio] = await Promise.all([
      this.database
        .sql`select metadata from app.learning_image_assets where id=any(${imageIds}::text[]) order by id`,
      this.database
        .sql`select metadata from app.learning_audio_assets where id=any(${audioIds}::text[]) order by id`,
    ]);
    return {
      images: images.map((row) => learningImageSchema.parse(row.metadata)),
      audio: audio.map((row) => learningAudioSchema.parse(row.metadata)),
    };
  }
  async units(filter: LearningAdminFilter) {
    const rows = await this.database
      .sql`select u.id,u.role_key,u.level_key,u.current_version,u.published,v.content_hash,v.payload->>'title' as title,v.payload->'authorship'->>'kind' as authorship,jsonb_array_length(v.payload->'questions') as questions,count(*) over()::int as total from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version where (${filter.role ?? null}::text is null or u.role_key=${filter.role ?? null}) and (${filter.level ?? null}::text is null or u.level_key=${filter.level ?? null}) order by u.role_key,u.level_key,u.id limit ${filter.limit} offset ${filter.offset}`;
    return {
      items: rows.map((row) => {
        const item = { ...row };
        delete item.total;
        return item;
      }),
      total: Number(rows[0]?.total ?? 0),
    };
  }
  async unit(id: string, version?: number) {
    const [row] = await this.database
      .sql`select v.payload,v.content_hash,u.current_version,u.published from app.learning_units u join app.learning_unit_versions v on v.unit_id=u.id where u.id=${id} and v.version=coalesce(${version ?? null}::integer,u.current_version)`;
    if (!row) return undefined;
    const versions = await this.database
      .sql`select version,content_hash from app.learning_unit_versions where unit_id=${id} order by version desc`;
    return {
      unit: unitSchema.parse(row.payload),
      contentHash: String(row.content_hash),
      currentVersion: Number(row.current_version),
      published: Boolean(row.published),
      versions,
    };
  }
  async revisionDraft(id: string) {
    const [row] = await this.database
      .sql`select payload from app.learning_generation_edits where revised_job_id=${id}`;
    return row ? unitSchema.parse(row.payload) : null;
  }
  async jobs(filter: LearningAdminFilter) {
    const rows = await this.database
      .sql`select j.id,j.role_key,j.level_key,j.status,j.attempts,j.candidate_hash,coalesce(j.candidate->>'title',e.payload->>'title') as title,j.last_error_code,j.created_at,(e.id is not null) as is_revision,count(*) over()::int as total from app.learning_generation_jobs j left join app.learning_generation_edits e on e.revised_job_id=j.id where (${filter.role ?? null}::text is null or role_key=${filter.role ?? null}) and (${filter.level ?? null}::text is null or level_key=${filter.level ?? null}) and (${filter.status ?? null}::text is null or status=${filter.status ?? null}) order by j.created_at desc,j.id desc limit ${filter.limit} offset ${filter.offset}`;
    return {
      items: rows.map((row) => {
        const item = { ...row };
        delete item.total;
        return item;
      }),
      total: Number(rows[0]?.total ?? 0),
    };
  }
}
