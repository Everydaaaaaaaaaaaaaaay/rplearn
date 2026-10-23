import type { DatabaseResource } from "../../db/client.js";
import { contentHash } from "./content.js";
import { loadExpansionCatalog } from "./expansion-catalog.js";
import { LearningEngineRepository } from "./engine-repository.js";
import type { LearningImageAsset } from "./images.js";

export class LearningExpansionRepository {
  constructor(private readonly database: DatabaseResource) {}

  async publish(
    expectedHash: string,
    batch: string,
    images: readonly LearningImageAsset[] = [],
  ) {
    const catalog = loadExpansionCatalog(batch);
    if (catalog.hash !== expectedHash) throw new Error("Expansion hash mismatch");
    // [] verifies all referenced audio against already archived server metadata.
    await new LearningEngineRepository(this.database).publishBatch(
      catalog.units,
      [],
      images,
    );
    return { batch, units: catalog.units.length, hash: catalog.hash };
  }

  /** One transaction withdraws only this run's exact known IDs; no payload/answer/reward is deleted. */
  async withdraw(batch?: string) {
    const { units } = loadExpansionCatalog(batch);
    const ids = units.map((u) => u.id);
    return this.database.sql.begin(async (sql) => {
      await sql`set local lock_timeout='5s'`;
      await sql`set local statement_timeout='30s'`;
      await sql`select pg_advisory_xact_lock(hashtextextended('learning-publication',0))`;
      const rows = await sql<{ id: string; content_hash: string }[]>`
        select u.id,v.content_hash from app.learning_units u
        join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version
        where u.id=any(${ids})`;
      // A later reviewed version still belongs to this new cohort and must be
      // withdrawable. Report hash drift without blocking the requested rollback.
      const expected = new Map(units.map((u) => [u.id, contentHash(u)]));
      const changedPublishedHashes = rows.filter(
        (row) => expected.get(row.id) !== row.content_hash,
      ).length;
      const withdrawn =
        await sql`update app.learning_units set published=false where id=any(${ids}) and published returning id`;
      const attempts = await sql<
        {
          user_id: string;
          character_id: string;
          cycle_id: string;
          first_completed_at: unknown;
        }[]
      >`
        update app.learning_attempts set superseded_at=now(),revision=revision+1
        where unit_id=any(${ids}) and superseded_at is null
        returning user_id,character_id,cycle_id,first_completed_at`;
      for (const attempt of attempts.filter((a) => a.first_completed_at === null))
        await sql`update app.learning_characters set cycle_id=gen_random_uuid(),revision=revision+1
          where user_id=${attempt.user_id} and character_id=${attempt.character_id} and cycle_id=${attempt.cycle_id}`;
      return {
        run: "2026-10-24",
        batch: batch ?? "all",
        withdrawnUnits: withdrawn.length,
        changedPublishedHashes,
        retiredAttempts: attempts.length,
        preservedAnswersAndRewards: true,
      };
    });
  }
}
