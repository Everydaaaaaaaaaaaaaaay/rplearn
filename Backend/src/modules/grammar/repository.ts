import type { DatabaseResource } from "../../db/client.js";
import { insertPreparedJob } from "../jobs/transactional-enqueue.js";
import { conceptId, hash, patternIdentity } from "./identity.js";
import type { CatalogSnapshot, GrammarConcept, GrammarRepository } from "./types.js";

export class SharedGrammarRepository implements GrammarRepository {
  constructor(
    private readonly database: DatabaseResource,
    private readonly seed: GrammarConcept[],
  ) {}
  async snapshot(): Promise<CatalogSnapshot> {
    const rows = await this.database.sql<{ point: GrammarConcept }[]>`
      select point from app.shared_grammar_concepts order by id`;
    const points = [...this.seed, ...rows.map((r) => r.point)];
    return { points, revision: hash(points) };
  }
  async resolution(fingerprint: string): Promise<string | null | undefined> {
    const [row] = await this.database.sql<{ concept_id: string | null }[]>`
      select concept_id from app.shared_grammar_aliases where fingerprint = ${fingerprint}`;
    return row?.concept_id;
  }
  async schedule(
    fingerprint: string,
    proposal: Parameters<GrammarRepository["schedule"]>[1],
    prepare: Parameters<GrammarRepository["schedule"]>[2],
  ) {
    await this.database.sql.begin(async (sql) => {
      const [row] =
        await sql`insert into app.shared_grammar_aliases(fingerprint,proposal)
        values (${fingerprint},${JSON.stringify(proposal)}::jsonb) on conflict (fingerprint) do nothing returning fingerprint`;
      if (row !== undefined) await insertPreparedJob(sql, prepare());
    });
  }
  async reconcile(
    input: Parameters<GrammarRepository["reconcile"]>[0],
  ): Promise<string | null> {
    return this.database.sql.begin(async (sql) => {
      await sql`select pg_advisory_xact_lock(734812093)`;
      const [alias] = await sql<{ concept_id: string | null; reviewed: boolean }[]>`
        select concept_id,reviewed from app.shared_grammar_aliases where fingerprint = ${input.fingerprint}`;
      if (alias?.reviewed === true) return alias.concept_id;
      const rows = await sql<
        { point: GrammarConcept }[]
      >`select point from app.shared_grammar_concepts order by id`;
      const points = [...this.seed, ...rows.map((r) => r.point)];
      let id: string | null =
        points.find((p) => patternIdentity(p) === input.fingerprint)?.id ?? null;
      if (id === null && input.decision.verdict === "equivalent") {
        id = points.find((p) => p.id === input.decision.existingId)?.id ?? null;
      }
      // An independent review must use this exact catalog; a concurrent addition
      // sends the proposal to the pending set instead of publishing a possible synonym.
      if (
        id === null &&
        input.decision.verdict === "distinct" &&
        input.decision.identity === input.proposal.identity &&
        hash(points) === input.snapshotRevision
      ) {
        id = conceptId(input.proposal.identity);
        const point = {
          id,
          title: input.proposal.title,
          explanationZh: input.proposal.explanationZh,
          triggers: input.proposal.triggers,
          examples: input.proposal.examples,
          patterns: input.proposal.patterns,
          related: [],
        };
        const [stored] = await sql<{ id: string }[]>`
          insert into app.shared_grammar_concepts(id,identity,pattern_fingerprint,point)
          values (${id},${input.proposal.identity},${input.fingerprint},${JSON.stringify(point)}::jsonb)
          on conflict (identity) do update set identity = excluded.identity returning id`;
        id = stored?.id ?? null;
      }
      await sql`insert into app.shared_grammar_aliases(fingerprint,concept_id,proposal,reviewed)
        values (${input.fingerprint},${id},${id === null ? JSON.stringify(input.proposal) : null}::jsonb,true)
        on conflict (fingerprint) do update set concept_id = excluded.concept_id,proposal = excluded.proposal,reviewed = true`;
      return id;
    });
  }
}
