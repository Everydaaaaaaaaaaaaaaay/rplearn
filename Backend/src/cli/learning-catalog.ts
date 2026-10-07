import "dotenv/config";
import {
  requireMaintenanceScope,
  maintenanceStage,
} from "../infrastructure/maintenance.js";
import { fileURLToPath } from "node:url";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { loadCuratedCatalog } from "../modules/learning/catalog.js";
import { LearningEngineRepository } from "../modules/learning/engine-repository.js";
import { createMediaObjectStore } from "../modules/media/object-store.js";
import { uploadLearningAudio } from "../modules/learning/audio.js";

import { uploadLearningImages } from "../modules/learning/images.js";

async function main(): Promise<void> {
  const [command, expectedHash, ...extra] = process.argv.slice(2);
  if (
    !["validate", "publish"].includes(command ?? "") ||
    extra.length > 0 ||
    (command === "validate" && expectedHash !== undefined)
  )
    throw new Error(
      "用法：learning-catalog validate；或 learning-catalog publish 已验证的目录哈希。",
    );
  // 源码与构建后的 CLI 都从 Backend 根目录下的同一份版本化目录读取。
  const directory = fileURLToPath(new URL("../../config/learning/", import.meta.url));
  await requireMaintenanceScope();
  const catalog = await maintenanceStage("校验目录", () =>
    loadCuratedCatalog(directory),
  );
  if (command === "publish") {
    if (expectedHash !== catalog.hash)
      throw new Error("发布哈希不匹配；请先验证当前目录，使用输出的完整哈希。");
    const config = loadConfig();
    if (catalog.audioAssets.length > 0 || catalog.imageAssets.length > 0) {
      if (!config.mediaStorageEnabled)
        throw new Error("未启用对象存储，不能发布视听单元。");
      const store = createMediaObjectStore(config);
      await maintenanceStage("校验并上传音频", () =>
        uploadLearningAudio(catalog.audioAssets, store),
      );
      await maintenanceStage("校验并上传图片", () =>
        uploadLearningImages(catalog.imageAssets, store),
      );
    }
    const database = createDatabase(config);
    try {
      await maintenanceStage("提交目录事务", () =>
        new LearningEngineRepository(database).publishBatch(
          catalog.units,
          catalog.audioAssets.map((asset) => asset.metadata),
          catalog.imageAssets.map((asset) => asset.metadata),
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
        catalogHash: catalog.hash,
        summary: catalog.summary,
        note:
          command === "publish"
            ? "完整目录已在一个事务内发布；相同版本重放不重复写入。"
            : "结构、来源登记、审核绑定与判题样例已通过；不等同于独立教研或真人教学效果验证。",
      },
      null,
      2,
    ) + "\n",
  );
}

void main().catch((error: unknown) => {
  process.stderr.write(
    `${error instanceof Error ? error.message : "学习题库处理失败。"}\n`,
  );
  process.exitCode = 1;
});
