import type { DatabaseResource } from "../../db/client.js";
import type { PreparedJob } from "../jobs/types.js";
import { insertPreparedJob } from "../jobs/transactional-enqueue.js";
import type { LearnerExample } from "./catalog-repository.js";

export type LexicalBaseline = Readonly<{
  lemma: string;
  definition: string;
  meaning: string;
  forms: readonly string[];
  existingExamples: readonly string[];
}>;
export type ExampleGeneration = Readonly<{
  revision: number;
  status: "pending" | "ready" | "failed";
  examples: readonly LearnerExample[];
  retryAfter: string | null;
  failureCode: string | null;
}>;
type GenerationRow = Readonly<{
  revision: number;
  status: "pending" | "ready" | "failed";
  examples: LearnerExample[];
  retry_after: string | null;
  failure_code: string | null;
}>;
const record = (r: GenerationRow): ExampleGeneration => ({
  revision: r.revision,
  status: r.status,
  examples: r.examples,
  retryAfter: r.retry_after === null ? null : new Date(r.retry_after).toISOString(),
  failureCode: r.failure_code,
});

export class DictionaryExampleGenerationRepository {
  constructor(private readonly database: DatabaseResource) {}

  async baseline(lemma: string): Promise<LexicalBaseline | undefined> {
    const [row] = await this.database.sql<
      {
        lemma: string;
        definition: string;
        meaning: string;
        forms: string[];
        existing_examples: string[];
      }[]
    >`
      select lemma, definition, meaning, forms, existing_examples from app.dictionary_example_lexicon where lemma = ${lemma}`;
    return row === undefined
      ? undefined
      : {
          lemma: row.lemma,
          definition: row.definition,
          meaning: row.meaning,
          forms: row.forms,
          existingExamples: row.existing_examples,
        };
  }

  async find(lemma: string): Promise<ExampleGeneration | undefined> {
    const [row] = await this.database.sql<GenerationRow[]>`
      select g.revision, g.examples,
        case when g.status = 'pending' and (j.id is null or j.status in ('dead','cancelled')) then 'failed' else g.status end as status,
        coalesce(g.retry_after, case when (j.id is null or j.status in ('dead','cancelled')) then coalesce(j.updated_at,g.updated_at) + interval '1 hour' else null end) as retry_after,
        coalesce(g.failure_code, j.last_error) as failure_code
        from app.dictionary_example_generations g left join app.jobs j on j.id = g.job_id where g.lemma = ${lemma}`;
    return row === undefined ? undefined : record(row);
  }

  async schedule(
    lemma: string,
    prepare: (revision: number) => Promise<PreparedJob>,
  ): Promise<ExampleGeneration> {
    return this.database.sql.begin(async (sql) => {
      // All API instances serialize on the authoritative lemma row, not Redis.
      await sql`select lemma from app.dictionary_example_lexicon where lemma = ${lemma} for update`;
      const [old] = await sql<GenerationRow[]>`select g.revision, g.examples,
        case when g.status = 'pending' and (j.id is null or j.status in ('dead','cancelled')) then 'failed' else g.status end as status,
        coalesce(g.retry_after, case when (j.id is null or j.status in ('dead','cancelled')) then coalesce(j.updated_at,g.updated_at) + interval '1 hour' else null end) as retry_after,
        coalesce(g.failure_code, j.last_error) as failure_code
        from app.dictionary_example_generations g left join app.jobs j on j.id = g.job_id where g.lemma = ${lemma}`;
      if (
        old !== undefined &&
        (old.status !== "failed" ||
          (old.retry_after !== null && Date.parse(old.retry_after) > Date.now()))
      )
        return record(old);
      const revision = (old?.revision ?? 0) + 1;
      const job = await prepare(revision);
      await insertPreparedJob(sql, job);
      const [row] = await sql<GenerationRow[]>`
        insert into app.dictionary_example_generations (lemma, revision, job_id) values (${lemma}, ${revision}, ${job.id})
        on conflict (lemma) do update set revision = excluded.revision, job_id = excluded.job_id, status = 'pending',
          examples = '[]', attempts = 0, failure_code = null, retry_after = null, updated_at = now()
        returning revision, status, examples, retry_after, failure_code`;
      if (row === undefined) throw new Error("DictionaryGenerationNotScheduled");
      return record(row);
    });
  }

  async complete(
    lemma: string,
    revision: number,
    examples: readonly LearnerExample[],
    model: string,
    attempt: number,
  ): Promise<void> {
    await this.database.sql`
      update app.dictionary_example_generations set status = 'ready', examples = ${JSON.stringify(examples)}::jsonb,
        model = ${model}, attempts = ${attempt}, failure_code = null, retry_after = null, updated_at = now()
      where lemma = ${lemma} and revision = ${revision} and status = 'pending'`;
  }

  async fail(
    lemma: string,
    revision: number,
    attempt: number,
    code: string,
  ): Promise<void> {
    await this.database.sql`
      update app.dictionary_example_generations set attempts = ${attempt}, failure_code = ${code}, updated_at = now(),
        status = ${attempt >= 3 ? "failed" : "pending"},
        retry_after = case when ${attempt} >= 3 then now() + interval '1 hour' else null end
      where lemma = ${lemma} and revision = ${revision} and status = 'pending'`;
  }
}
export type GenerationRepository = Pick<
  DictionaryExampleGenerationRepository,
  "baseline" | "find" | "schedule" | "complete" | "fail"
>;
