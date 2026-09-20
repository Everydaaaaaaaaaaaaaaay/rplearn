import type { DatabaseResource } from "../../db/client.js";

export type LearnerExample = Readonly<{
  rank: number;
  partOfSpeech: string;
  definition: string;
  sentence: string;
  sentenceZhHans: string;
  contextualMeaningZhHans: string;
}>;

/** The shared reviewed seed is authoritative; no paid generation on reads. */
export class DictionaryExampleCatalogRepository {
  constructor(private readonly database: DatabaseResource) {}

  async find(lemma: string): Promise<readonly LearnerExample[]> {
    const rows = await this.database.sql<
      {
        stable_sense_id: string;
        part_of_speech: string;
        sense_definition_en: string;
        sentence: string;
        sentence_zh_hans: string;
        contextual_meaning_zh_hans: string;
      }[]
    >`
      select distinct on (stable_sense_id)
        stable_sense_id, part_of_speech, sense_definition_en, sentence,
        sentence_zh_hans, contextual_meaning_zh_hans
      from app.dictionary_example_translations
      where lemma = ${lemma}
        and dictionary_source = 'lingotrip-learner-examples'
        and dictionary_version = 'v1'
        and generation_kind = 'trusted_precomputed' and status = 'ready'
        and stable_sense_id is not null and sense_definition_en is not null
        and sentence_zh_hans is not null and contextual_meaning_zh_hans is not null
      order by stable_sense_id, completed_at desc
      limit 4
    `;
    return rows
      .flatMap((row) => {
        const rank = Number(/^.+?-(-\d+)-/.exec(row.stable_sense_id)?.[1]);
        if (!Number.isInteger(rank) || rank >= 0) return [];
        return [
          {
            rank,
            partOfSpeech: row.part_of_speech,
            definition: row.sense_definition_en,
            sentence: row.sentence,
            sentenceZhHans: row.sentence_zh_hans,
            contextualMeaningZhHans: row.contextual_meaning_zh_hans,
          },
        ];
      })
      .sort((a, b) => a.rank - b.rank);
  }
}
