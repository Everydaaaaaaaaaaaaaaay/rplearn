import "dotenv/config";
import {
  requireMaintenanceScope,
  maintenanceStage,
} from "../infrastructure/maintenance.js";
import { loadGaokaoCatalog } from "../modules/learning/gaokao-catalog.js";
import { gaokaoCatalog } from "../modules/learning/gaokao-policy.js";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { createMediaObjectStore } from "../modules/media/object-store.js";
import { uploadLearningImages } from "../modules/learning/images.js";
import { LearningEngineRepository } from "../modules/learning/engine-repository.js";

async function main() {
  const [operation, hash, ...extra] = process.argv.slice(2);
  if (
    !["validate", "publish"].includes(operation ?? "") ||
    extra.length ||
    (operation === "publish" && !/^[a-f0-9]{64}$/.test(hash ?? "")) ||
    (operation === "validate" && hash)
  )
    throw new Error(
      "用法：learning-gaokao validate；learning-gaokao publish 已核目录哈希。",
    );
  await requireMaintenanceScope();
  const catalog = await maintenanceStage("核验高考题型完整练习", loadGaokaoCatalog);
  if (operation === "publish") {
    if (hash !== catalog.hash) throw new Error("高考目录哈希不符，已停止发布。");
    const config = loadConfig();
    if (!config.mediaStorageEnabled)
      throw new Error("缺少必要图表的对象存储，不能发布。");
    await maintenanceStage("上传高考原图", () =>
      uploadLearningImages(catalog.imageAssets, createMediaObjectStore(config)),
    );
    const db = createDatabase(config);
    try {
      await maintenanceStage("发布高考题型练习事务", () =>
        new LearningEngineRepository(db).publishBatch(
          catalog.units,
          [],
          catalog.imageAssets.map((a) => a.metadata),
        ),
      );
    } finally {
      await db.close();
    }
  }
  console.log(
    JSON.stringify({
      operation,
      hash: catalog.hash,
      units: catalog.units.length,
      pastPaperPractices: gaokaoCatalog().practices.filter(
        (p) => p.kind === "past-paper",
      ).length,
      authoredPractices: gaokaoCatalog().practices.filter((p) => p.kind === "authored")
        .length,
      uniqueQuestions: new Set(
        catalog.units.flatMap((u) => u.questions.map((q) => q.id)),
      ).size,
    }),
  );
}
void main().catch((error: unknown) => {
  console.error(error instanceof Error ? error.message : "高考目录操作失败。");
  process.exitCode = 1;
});
