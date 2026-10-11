import "dotenv/config";
import {
  requireMaintenanceScope,
  maintenanceStage,
} from "../infrastructure/maintenance.js";
import { fileURLToPath } from "node:url";
import { loadBankCatalog } from "../modules/learning/bank-catalog.js";
import { LearningBankRepository } from "../modules/learning/bank-repository.js";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";

async function main() {
  const [command, expectedHash, ...extra] = process.argv.slice(2);
  await requireMaintenanceScope();
  if (command === "pause" && !expectedHash && extra.length === 0) {
    const database = createDatabase(loadConfig());
    try {
      await new LearningBankRepository(database).setEnabled(false);
    } finally {
      await database.close();
    }
    process.stdout.write("公共组卷已暂停，已有挑战与补答继续使用原快照。\n");
    return;
  }
  if (
    !["validate", "publish"].includes(command ?? "") ||
    extra.length ||
    (command === "validate" && expectedHash)
  )
    throw new Error("用法：learning-bank validate；learning-bank publish 已验证哈希。");
  const catalog = await maintenanceStage("校验公共题库", () =>
    loadBankCatalog(fileURLToPath(new URL("../../config/learning/", import.meta.url))),
  );
  if (command === "publish") {
    if (expectedHash !== catalog.hash) throw new Error("公共题库发布哈希不一致。");
    const database = createDatabase(loadConfig());
    try {
      await maintenanceStage("提交公共题库事务", () =>
        new LearningBankRepository(database).importCatalog(
          catalog.entries,
          catalog.blueprints,
          catalog.revisions,
        ),
      );
    } finally {
      await database.close();
    }
  }
  process.stdout.write(
    JSON.stringify({
      operation: command,
      hash: catalog.hash,
      questions: catalog.entries.length,
      blueprints: catalog.blueprints.length,
      revisions: catalog.revisions.length,
    }) + "\n",
  );
}
void main().catch((error: unknown) => {
  process.stderr.write(
    `${error instanceof Error ? error.message : "公共题库操作失败。"}\n`,
  );
  process.exitCode = 1;
});
