import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import type { PreparedJob } from "../jobs/types.js";
import { insertPreparedJob } from "../jobs/transactional-enqueue.js";
import type {
  DictionaryTranslationCacheIdentity,
  GeneratedDictionaryTranslation,
} from "./types.js";

type TranslationRow = Readonly<{
  attempt_count: number;
  cache_key: string;
  candidate_meanings_text: string;
  completed_at: string | null;
  contextual_meaning_zh_hans: string | null;
  dictionary_source: string;
  dictionary_version: string;
  example_hash: string;
  generation_kind: "runtime" | "trusted_precomputed";
  lemma: string;
  part_of_speech: string;
  prompt_version: string;
  selected_meaning_index: number | null;
  sense_definition_en: string | null;
  sense_fingerprint: string;
  sentence: string;
  sentence_zh_hans: string | null;
  source_key: string;
  stable_sense_id: string | null;
  status: "failed" | "pending" | "ready";
  translation_model_version: string;
}>;

export type StoredDictionaryTranslation = Readonly<{
  attemptCount: number;
  cacheKey: string;
  candidateMeaningsZhHans: readonly string[];
  completedAt: string | null;
  contextualMeaningZhHans: string | null;
  dictionarySource: string;
  dictionaryVersion: string;
  exampleHash: string;
  generationKind: "runtime" | "trusted_precomputed";
  lemma: string;
  partOfSpeech: string;
  promptVersion: string;
  selectedMeaningIndex: number | null;
  senseDefinitionEn: string | null;
  senseFingerprint: string;
  sentence: string;
  sentenceZhHans: string | null;
  sourceKey: string;
  stableSenseId: string | null;
  status: "failed" | "pending" | "ready";
  translationModelVersion: string;
}>;

export type DictionaryTranslationRepositoryContract = Readonly<{
  complete: (
    cacheKey: string,
    attempt: number,
    translation: GeneratedDictionaryTranslation,
    now: Date,
  ) => Promise<boolean>;
  fail: (
    cacheKey: string,
    attempt: number,
    failureCode: string,
    now: Date,
  ) => Promise<void>;
  findPreferred: (
    sourceKey: string,
    currentCacheKey: string,
  ) => Promise<StoredDictionaryTranslation | undefined>;
  importTrusted: (
    identity: DictionaryTranslationCacheIdentity,
    translation: GeneratedDictionaryTranslation,
    now: Date,
  ) => Promise<StoredDictionaryTranslation>;
  loadForProcessing: (
    cacheKey: string,
    attempt: number,
  ) => Promise<StoredDictionaryTranslation | undefined>;
  schedule: (
    identity: DictionaryTranslationCacheIdentity,
    userId: string,
    prepareJob: (attempt: number) => PreparedJob,
  ) => Promise<StoredDictionaryTranslation>;
}>;

const rowSelection = `
  cache_key,
  source_key,
  lemma,
  part_of_speech,
  stable_sense_id,
  sense_fingerprint,
  example_hash,
  sentence,
  candidate_meanings_zh_hans::text as candidate_meanings_text,
  dictionary_source,
  dictionary_version,
  translation_model_version,
  prompt_version,
  generation_kind,
  status,
  sentence_zh_hans,
  contextual_meaning_zh_hans,
  selected_meaning_index,
  sense_definition_en,
  attempt_count,
  completed_at
`;

function mapRow(row: TranslationRow): StoredDictionaryTranslation {
  return {
    attemptCount: row.attempt_count,
    cacheKey: row.cache_key,
    candidateMeaningsZhHans: JSON.parse(row.candidate_meanings_text) as string[],
    completedAt:
      row.completed_at === null ? null : new Date(row.completed_at).toISOString(),
    contextualMeaningZhHans: row.contextual_meaning_zh_hans,
    dictionarySource: row.dictionary_source,
    dictionaryVersion: row.dictionary_version,
    exampleHash: row.example_hash,
    generationKind: row.generation_kind,
    lemma: row.lemma,
    partOfSpeech: row.part_of_speech,
    promptVersion: row.prompt_version,
    selectedMeaningIndex: row.selected_meaning_index,
    senseDefinitionEn: row.sense_definition_en,
    senseFingerprint: row.sense_fingerprint,
    sentence: row.sentence,
    sentenceZhHans: row.sentence_zh_hans,
    sourceKey: row.source_key,
    stableSenseId: row.stable_sense_id,
    status: row.status,
    translationModelVersion: row.translation_model_version,
  };
}

async function lockedRow(
  sql: TransactionSql,
  cacheKey: string,
): Promise<StoredDictionaryTranslation | undefined> {
  const rows = await sql.unsafe<TranslationRow[]>(
    `select ${rowSelection}
     from app.dictionary_example_translations
     where cache_key = $1
     for update`,
    [cacheKey],
  );
  return rows[0] === undefined ? undefined : mapRow(rows[0]);
}

export class DictionaryTranslationRepository implements DictionaryTranslationRepositoryContract {
  constructor(private readonly database: DatabaseResource) {}

  async findPreferred(
    sourceKey: string,
    currentCacheKey: string,
  ): Promise<StoredDictionaryTranslation | undefined> {
    const rows = await this.database.sql.unsafe<TranslationRow[]>(
      `select ${rowSelection}
       from app.dictionary_example_translations
       where source_key = $1
         and (
           (generation_kind = 'trusted_precomputed' and status = 'ready')
           or cache_key = $2
         )
       order by
         case
           when status = 'ready' and generation_kind = 'trusted_precomputed' then 0
           when status = 'ready' and cache_key = $2 then 1
           when status = 'pending' and cache_key = $2 then 2
           else 3
         end,
         completed_at desc nulls last
       limit 1`,
      [sourceKey, currentCacheKey],
    );
    return rows[0] === undefined ? undefined : mapRow(rows[0]);
  }

  async schedule(
    identity: DictionaryTranslationCacheIdentity,
    userId: string,
    prepareJob: (attempt: number) => PreparedJob,
  ): Promise<StoredDictionaryTranslation> {
    return this.database.sql.begin(async (sql) => {
      await sql`
        select pg_advisory_xact_lock(
          hashtextextended(${`dictionary-translation:${identity.cacheKey}`}, 0)
        )
      `;
      const existing = await lockedRow(sql, identity.cacheKey);
      if (existing?.status === "ready" || existing?.status === "pending") {
        return existing;
      }
      const attempt = (existing?.attemptCount ?? 0) + 1;
      if (existing === undefined) {
        await sql`
          insert into app.dictionary_example_translations (
            cache_key,
            source_key,
            lemma,
            part_of_speech,
            stable_sense_id,
            sense_fingerprint,
            sense_definition_en,
            example_hash,
            sentence,
            candidate_meanings_zh_hans,
            dictionary_source,
            dictionary_version,
            translation_model_version,
            prompt_version,
            generation_kind,
            status,
            requested_by_user_id,
            attempt_count
          )
          values (
            ${identity.cacheKey},
            ${identity.sourceKey},
            ${identity.lemma},
            ${identity.partOfSpeech},
            ${identity.stableSenseId ?? null},
            ${identity.senseFingerprint},
            ${identity.senseDefinitionEn ?? null},
            ${identity.exampleHash},
            ${identity.sentence},
            ${JSON.stringify(identity.candidateMeaningsZhHans)}::jsonb,
            ${identity.dictionarySource},
            ${identity.dictionaryVersion},
            ${identity.translationModelVersion},
            ${identity.promptVersion},
            'runtime',
            'pending',
            ${userId},
            ${attempt}
          )
        `;
      } else {
        await sql`
          update app.dictionary_example_translations
          set status = 'pending',
              requested_by_user_id = ${userId},
              attempt_count = ${attempt},
              failure_code = null,
              completed_at = null,
              updated_at = now()
          where cache_key = ${identity.cacheKey}
        `;
      }
      await insertPreparedJob(sql, prepareJob(attempt));
      const scheduled = await lockedRow(sql, identity.cacheKey);
      if (scheduled === undefined) {
        throw new Error("DictionaryTranslationScheduleFailed");
      }
      return scheduled;
    });
  }

  async loadForProcessing(
    cacheKey: string,
    attempt: number,
  ): Promise<StoredDictionaryTranslation | undefined> {
    const rows = await this.database.sql.unsafe<TranslationRow[]>(
      `select ${rowSelection}
       from app.dictionary_example_translations
       where cache_key = $1
         and attempt_count = $2
         and status = 'pending'`,
      [cacheKey, attempt],
    );
    return rows[0] === undefined ? undefined : mapRow(rows[0]);
  }

  async complete(
    cacheKey: string,
    attempt: number,
    translation: GeneratedDictionaryTranslation,
    now: Date,
  ): Promise<boolean> {
    const rows = await this.database.sql<{ cache_key: string }[]>`
      update app.dictionary_example_translations
      set status = 'ready',
          sentence_zh_hans = ${translation.sentenceZhHans},
          contextual_meaning_zh_hans = ${translation.contextualMeaningZhHans},
          selected_meaning_index = ${translation.selectedMeaningIndex ?? null},
          failure_code = null,
          completed_at = ${now.toISOString()},
          updated_at = ${now.toISOString()}
      where cache_key = ${cacheKey}
        and attempt_count = ${attempt}
        and status = 'pending'
      returning cache_key
    `;
    return rows.length === 1;
  }

  async fail(
    cacheKey: string,
    attempt: number,
    failureCode: string,
    now: Date,
  ): Promise<void> {
    await this.database.sql`
      update app.dictionary_example_translations
      set status = 'failed',
          failure_code = ${failureCode.slice(0, 160)},
          completed_at = ${now.toISOString()},
          updated_at = ${now.toISOString()}
      where cache_key = ${cacheKey}
        and attempt_count = ${attempt}
        and status = 'pending'
    `;
  }

  async importTrusted(
    identity: DictionaryTranslationCacheIdentity,
    translation: GeneratedDictionaryTranslation,
    now: Date,
  ): Promise<StoredDictionaryTranslation> {
    return this.database.sql.begin(async (sql) => {
      await sql`
        select pg_advisory_xact_lock(
          hashtextextended(${`dictionary-translation:${identity.cacheKey}`}, 0)
        )
      `;
      const existing = await lockedRow(sql, identity.cacheKey);
      if (existing?.status === "ready") {
        if (
          existing.sentenceZhHans !== translation.sentenceZhHans ||
          existing.contextualMeaningZhHans !== translation.contextualMeaningZhHans ||
          existing.selectedMeaningIndex !== (translation.selectedMeaningIndex ?? null)
        ) {
          throw new AppError({
            code: "IDEMPOTENCY_KEY_CONFLICT",
            message: "This translation cache key already has different content.",
            statusCode: 409,
          });
        }
        return existing;
      }
      await sql`
        insert into app.dictionary_example_translations (
          cache_key,
          source_key,
          lemma,
          part_of_speech,
          stable_sense_id,
          sense_fingerprint,
          sense_definition_en,
          example_hash,
          sentence,
          candidate_meanings_zh_hans,
          dictionary_source,
          dictionary_version,
          translation_model_version,
          prompt_version,
          generation_kind,
          status,
          sentence_zh_hans,
          contextual_meaning_zh_hans,
          selected_meaning_index,
          completed_at,
          attempt_count,
          updated_at
        )
        values (
          ${identity.cacheKey},
          ${identity.sourceKey},
          ${identity.lemma},
          ${identity.partOfSpeech},
          ${identity.stableSenseId ?? null},
          ${identity.senseFingerprint},
          ${identity.senseDefinitionEn ?? null},
          ${identity.exampleHash},
          ${identity.sentence},
          ${JSON.stringify(identity.candidateMeaningsZhHans)}::jsonb,
          ${identity.dictionarySource},
          ${identity.dictionaryVersion},
          ${identity.translationModelVersion},
          ${identity.promptVersion},
          'trusted_precomputed',
          'ready',
          ${translation.sentenceZhHans},
          ${translation.contextualMeaningZhHans},
          ${translation.selectedMeaningIndex ?? null},
          ${now.toISOString()},
          1,
          ${now.toISOString()}
        )
        on conflict (cache_key) do update
        set generation_kind = 'trusted_precomputed',
            status = 'ready',
            sentence_zh_hans = excluded.sentence_zh_hans,
            contextual_meaning_zh_hans = excluded.contextual_meaning_zh_hans,
            selected_meaning_index = excluded.selected_meaning_index,
            failure_code = null,
            completed_at = excluded.completed_at,
            updated_at = excluded.updated_at
      `;
      const imported = await lockedRow(sql, identity.cacheKey);
      if (imported === undefined) {
        throw new Error("DictionaryTranslationImportFailed");
      }
      return imported;
    });
  }
}
