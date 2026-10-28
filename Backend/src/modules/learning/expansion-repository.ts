import type { DatabaseResource } from "../../db/client.js";
import { contentHash, type LearningUnit } from "./content.js";
import {
  expansionNamespace,
  expansionRun,
  loadExpansionCatalog,
} from "./expansion-catalog.js";
import { LearningEngineRepository } from "./engine-repository.js";
import type { LearningImageAsset } from "./images.js";
import type { LearningAudioAsset } from "./audio.js";

export class LearningExpansionRepository {
  constructor(private readonly database: DatabaseResource) {}

  async publish(
    expectedHash: string,
    batch: string,
    images: readonly LearningImageAsset[] = [],
    run: string = expansionRun,
    audios: readonly LearningAudioAsset[] = [],
  ) {
    const catalog = loadExpansionCatalog(batch, false, run);
    if (catalog.hash !== expectedHash) throw new Error("Expansion hash mismatch");
    const selectedAudio = catalog.manifests.flatMap((m) =>
      (m.audioAssets ?? []).filter((a) => m.newAudioAssetIds?.includes(a.id)),
    );
    const audioDigest = (assets: readonly LearningAudioAsset[]) =>
      contentHash([...assets].sort((a, b) => a.id.localeCompare(b.id)));
    if (audioDigest(selectedAudio) !== audioDigest(audios))
      throw new Error("Expansion selected new audio metadata mismatch");
    // Only explicitly selected new clips may be archived. Reused clips must already exist.
    await new LearningEngineRepository(this.database).publishBatch(
      catalog.units,
      audios,
      images,
    );
    return { run, batch, units: catalog.units.length, hash: catalog.hash };
  }

  /** The full-run switch also works from an earlier compatible release/catalog. */
  async withdraw(batch?: string, run: string = expansionRun) {
    const namespace = expansionNamespace(run);
    // The full-run emergency switch reads IDs from PostgreSQL, not every new
    // payload. It remains bounded if the new catalog is huge, absent or broken.
    const units: LearningUnit[] = batch
      ? loadExpansionCatalog(batch, false, run).units
      : [];
    const ids = units.map((u) => u.id);
    return this.database.sql.begin(async (sql) => {
      await sql`set local lock_timeout='5s'`;
      await sql`set local statement_timeout='30s'`;
      await sql`select pg_advisory_xact_lock(hashtextextended('learning-publication',0))`;
      const rows = await sql<{ id: string; content_hash: string }[]>`
        select u.id,v.content_hash from app.learning_units u
        join app.learning_unit_versions v on v.unit_id=u.id and v.version=u.current_version
        where u.id=any(${ids}) or (${batch === undefined} and u.id like ${namespace + "%"})`;
      const targetIds = rows.map((row) => row.id);
      // A later reviewed version still belongs to this new cohort and must be
      // withdrawable. Report hash drift without blocking the requested rollback.
      const expected = new Map(units.map((u) => [u.id, contentHash(u)]));
      const changedPublishedHashes = batch
        ? rows.filter((row) => expected.get(row.id) !== row.content_hash).length
        : 0;
      const withdrawn =
        await sql`update app.learning_units set published=false where id=any(${targetIds}) and published returning id`;
      const attempts = await sql<
        {
          user_id: string;
          character_id: string;
          cycle_id: string;
          first_completed_at: unknown;
        }[]
      >`
        update app.learning_attempts set superseded_at=now(),revision=revision+1
        where unit_id=any(${targetIds}) and superseded_at is null
        returning user_id,character_id,cycle_id,first_completed_at`;
      for (const attempt of attempts.filter((a) => a.first_completed_at === null))
        await sql`update app.learning_characters set cycle_id=gen_random_uuid(),revision=revision+1
          where user_id=${attempt.user_id} and character_id=${attempt.character_id} and cycle_id=${attempt.cycle_id}`;
      return {
        run,
        batch: batch ?? "all",
        withdrawnUnits: withdrawn.length,
        changedPublishedHashes,
        targetScope: batch ? "exact-batch-ids" : "reserved-run-namespace",
        retiredAttempts: attempts.length,
        preservedAnswersAndRewards: true,
      };
    });
  }
}
