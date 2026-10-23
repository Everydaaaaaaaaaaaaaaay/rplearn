import "dotenv/config";
import { requireMaintenanceScope } from "../infrastructure/maintenance.js";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import {
  loadExpansionCatalog,
  loadExpansionImages,
} from "../modules/learning/expansion-catalog.js";
import { createMediaObjectStore } from "../modules/media/object-store.js";
import { uploadLearningImages } from "../modules/learning/images.js";
import { LearningExpansionRepository } from "../modules/learning/expansion-repository.js";

async function main() {
  const [action, batch, hash, ...extra] = process.argv.slice(2);
  if (
    !["validate", "publish", "withdraw"].includes(action ?? "") ||
    extra.length ||
    (batch && batch !== "all" && !/^b[0-9]{3}$/.test(batch)) ||
    (action === "publish" &&
      (!batch || batch === "all" || !/^[a-f0-9]{64}$/.test(hash ?? ""))) ||
    (action !== "publish" && hash)
  )
    throw new Error(
      "Use learning-expansion validate [batch]; publish batch hash; withdraw [batch|all]",
    );
  await requireMaintenanceScope();
  const selected = batch === "all" ? undefined : batch;
  const catalog = loadExpansionCatalog(selected);
  if (action === "validate") {
    for (const manifest of catalog.manifests) await loadExpansionImages(manifest.batch);
    console.log(
      JSON.stringify({
        action,
        batch: batch ?? "all",
        hash: catalog.hash,
        units: catalog.units.length,
        questions: catalog.units.reduce((n, u) => n + u.questions.length, 0),
      }),
    );
    return;
  }
  const config = loadConfig();
  const db = createDatabase(config);
  try {
    const repository = new LearningExpansionRepository(db);
    if (action === "publish") {
      if (!hash || !selected) throw new Error("Missing expansion batch/hash");
      if (hash !== catalog.hash) throw new Error("Expansion hash mismatch");
      const images = await loadExpansionImages(selected);
      if (images.length) {
        if (!config.mediaStorageEnabled)
          throw new Error("New images need object storage");
        await uploadLearningImages(images, createMediaObjectStore(config));
      }
      console.log(
        JSON.stringify(
          await repository.publish(
            hash,
            selected,
            images.map((a) => a.metadata),
          ),
        ),
      );
    } else console.log(JSON.stringify(await repository.withdraw(selected)));
  } finally {
    await db.close();
  }
}
void main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : "Expansion operation failed");
  process.exitCode = 1;
});
