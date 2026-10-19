import "dotenv/config";
import { fileURLToPath } from "node:url";
import {
  requireMaintenanceScope,
  maintenanceStage,
} from "../infrastructure/maintenance.js";
import { loadOriginalCatalog } from "../modules/learning/original-catalog.js";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { LearningEngineRepository } from "../modules/learning/engine-repository.js";
import { createMediaObjectStore } from "../modules/media/object-store.js";
import { uploadLearningAudio } from "../modules/learning/audio.js";
import { uploadLearningImages } from "../modules/learning/images.js";

async function main() {
  const [command, arg, batch, ...extra] = process.argv.slice(2);
  const batchID = command === "validate" ? arg : batch;
  if (
    !["validate", "publish"].includes(command ?? "") ||
    extra.length ||
    (command === "validate" && batch) ||
    (batchID && !/^b[0-9]{3}$/.test(batchID)) ||
    (command === "publish" && (!batchID || !/^[a-f0-9]{64}$/.test(arg ?? "")))
  )
    throw new Error(
      "用法：learning-originals validate [b000]；learning-originals publish 已核哈希 b000。发布按有界批次进行。",
    );
  await requireMaintenanceScope();
  const directory = fileURLToPath(new URL("../../config/learning/", import.meta.url));
  const catalog = await maintenanceStage("核验原创完整组", () =>
    loadOriginalCatalog(directory, batchID),
  );
  // Release parsing/verification temporaries before allocating an upload body.
  globalThis.gc?.();
  if (command === "publish") {
    if (arg !== catalog.hash) throw new Error("原创批次哈希不符，已停止发布。");
    const config = loadConfig();
    if (catalog.audioAssets.length || catalog.imageAssets.length) {
      if (!config.mediaStorageEnabled)
        throw new Error("缺对象存储，不发布缺媒体单元。");
      const store = createMediaObjectStore(config);
      await maintenanceStage("上传原创音轨", () =>
        uploadLearningAudio(catalog.audioAssets, store),
      );
      await maintenanceStage("上传原创图片", () =>
        uploadLearningImages(catalog.imageAssets, store),
      );
    }
    const database = createDatabase(config);
    try {
      await maintenanceStage("发布原创批次事务", () =>
        new LearningEngineRepository(database).publishBatch(
          catalog.units,
          catalog.audioAssets.map((a) => a.metadata),
          catalog.imageAssets.map((a) => a.metadata),
        ),
      );
    } finally {
      await database.close();
    }
  }
  process.stdout.write(
    JSON.stringify(
      {
        operation: command,
        batch: batchID ?? "all",
        catalogHash: catalog.hash,
        units: catalog.units.length,
        responses: catalog.units.reduce((n, u) => n + u.questions.length, 0),
        note: "完整输入、作者审核绑定和已列答案回填通过；不代表独立教研、学生或商业效度。",
      },
      null,
      2,
    ) + "\n",
  );
}
void main().catch((error: unknown) => {
  process.stderr.write(
    `${error instanceof Error ? error.message : "原创题组处理失败。"}\n`,
  );
  process.exitCode = 1;
});
