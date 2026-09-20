import { sql } from "drizzle-orm";
import {
  check,
  index,
  integer,
  jsonb,
  text,
  timestamp,
  uuid,
} from "drizzle-orm/pg-core";
import { applicationSchema } from "../../db/schema.js";
import { users } from "../../db/user-schema.js";

export const dictionaryTranslationStatus = applicationSchema.enum(
  "dictionary_translation_status",
  ["pending", "ready", "failed"],
);

export const dictionaryExampleTranslations = applicationSchema.table(
  "dictionary_example_translations",
  {
    attemptCount: integer("attempt_count").default(1).notNull(),
    cacheKey: text("cache_key").primaryKey(),
    candidateMeaningsZhHans: jsonb("candidate_meanings_zh_hans").notNull(),
    completedAt: timestamp("completed_at", {
      mode: "date",
      withTimezone: true,
    }),
    contextualMeaningZhHans: text("contextual_meaning_zh_hans"),
    createdAt: timestamp("created_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
    dictionarySource: text("dictionary_source").notNull(),
    dictionaryVersion: text("dictionary_version").notNull(),
    exampleHash: text("example_hash").notNull(),
    failureCode: text("failure_code"),
    generationKind: text("generation_kind").notNull(),
    lemma: text("lemma").notNull(),
    partOfSpeech: text("part_of_speech").notNull(),
    promptVersion: text("prompt_version").notNull(),
    requestedByUserId: uuid("requested_by_user_id").references(() => users.id, {
      onDelete: "set null",
    }),
    selectedMeaningIndex: integer("selected_meaning_index"),
    senseDefinitionEn: text("sense_definition_en"),
    senseFingerprint: text("sense_fingerprint").notNull(),
    sentence: text("sentence").notNull(),
    sentenceZhHans: text("sentence_zh_hans"),
    sourceKey: text("source_key").notNull(),
    stableSenseId: text("stable_sense_id"),
    status: dictionaryTranslationStatus("status").default("pending").notNull(),
    translationModelVersion: text("translation_model_version").notNull(),
    updatedAt: timestamp("updated_at", {
      mode: "date",
      withTimezone: true,
    })
      .defaultNow()
      .notNull(),
  },
  (table) => [
    check(
      "dictionary_translations_cache_key_length",
      sql`length(${table.cacheKey}) = 64`,
    ),
    check(
      "dictionary_translations_source_key_length",
      sql`length(${table.sourceKey}) = 64`,
    ),
    check(
      "dictionary_translations_example_hash_length",
      sql`length(${table.exampleHash}) = 64`,
    ),
    check(
      "dictionary_translations_sense_hash_length",
      sql`length(${table.senseFingerprint}) = 64`,
    ),
    check("dictionary_translations_attempt_positive", sql`${table.attemptCount} > 0`),
    check(
      "dictionary_translations_generation_kind",
      sql`${table.generationKind} in ('runtime', 'trusted_precomputed')`,
    ),
    check(
      "dictionary_translations_ready_output",
      sql`(
        ${table.status} = 'ready'
        and ${table.sentenceZhHans} is not null
        and ${table.contextualMeaningZhHans} is not null
        and ${table.completedAt} is not null
      ) or (
        ${table.status} <> 'ready'
        and ${table.sentenceZhHans} is null
        and ${table.contextualMeaningZhHans} is null
        and ${table.selectedMeaningIndex} is null
      )`,
    ),
    index("dictionary_translations_lemma_catalog_index").on(
      table.lemma,
      table.dictionarySource,
      table.dictionaryVersion,
      table.generationKind,
      table.status,
    ),
    index("dictionary_translations_source_status_index").on(
      table.sourceKey,
      table.status,
      table.generationKind,
      table.completedAt,
    ),
    index("dictionary_translations_status_updated_index").on(
      table.status,
      table.updatedAt,
    ),
    index("dictionary_translations_requester_index").on(
      table.requestedByUserId,
      table.createdAt,
    ),
  ],
);

export const dictionaryExampleLexicon = applicationSchema.table(
  "dictionary_example_lexicon",
  {
    lemma: text("lemma").primaryKey(),
    definition: text("definition").notNull(),
    meaning: text("meaning").notNull(),
    forms: jsonb("forms")
      .notNull()
      .default(sql`'[]'`),
    existingExamples: jsonb("existing_examples")
      .notNull()
      .default(sql`'[]'`),
    sourceVersion: text("source_version").notNull(),
  },
  (table) => [
    check(
      "dictionary_example_lexicon_existing_examples_check",
      sql`jsonb_typeof(${table.existingExamples}) = 'array' AND jsonb_array_length(${table.existingExamples}) <= 2`,
    ),
  ],
);

export const dictionaryExampleGenerations = applicationSchema.table(
  "dictionary_example_generations",
  {
    lemma: text("lemma")
      .primaryKey()
      .references(() => dictionaryExampleLexicon.lemma),
    revision: integer("revision").notNull().default(1),
    // The cross-module ON DELETE SET NULL constraint is owned by migration 0025.
    jobId: uuid("job_id"),
    status: text("status").notNull().default("pending"),
    examples: jsonb("examples")
      .notNull()
      .default(sql`'[]'`),
    attempts: integer("attempts").notNull().default(0),
    failureCode: text("failure_code"),
    retryAfter: timestamp("retry_after", { withTimezone: true }),
    model: text("model"),
    promptVersion: text("prompt_version")
      .notNull()
      .default("learner-examples-runtime-v1"),
    updatedAt: timestamp("updated_at", { withTimezone: true }).notNull().defaultNow(),
  },
  (table) => [
    check(
      "dictionary_example_generations_status_check",
      sql`${table.status} IN ('pending','ready','failed')`,
    ),
    check(
      "dictionary_example_generations_examples_check",
      sql`jsonb_typeof(${table.examples}) = 'array' AND jsonb_array_length(${table.examples}) <= 2`,
    ),
  ],
);
