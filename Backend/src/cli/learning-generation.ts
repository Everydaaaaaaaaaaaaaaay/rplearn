import "dotenv/config";
import { fileURLToPath } from "node:url";
import { readFile } from "node:fs/promises";
import { z } from "zod";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { LearningGenerationRepository } from "../modules/learning/generation-repository.js";
import { loadGenerationBlueprints } from "../modules/learning/generation-content.js";
import { createLearningGenerationProcessor } from "../modules/learning/generation-processor.js";
import { createLearningEditorialCompletion } from "../modules/ai/editorial-service.js";

async function main() {
  const [command, value, ...extra] = process.argv.slice(2);
  if (
    !command ||
    extra.length ||
    !["list", "run", "inspect", "publish", "reject"].includes(command) ||
    (["run", "list"].includes(command) ? value !== undefined : !value)
  )
    throw new Error(
      "用法：learning-generation list；run；inspect 任务UUID；publish 审核JSON文件；reject 退回JSON文件。",
    );
  const config = loadConfig(),
    database = createDatabase(config);
  try {
    const repository = new LearningGenerationRepository(database);
    if (command === "list") {
      process.stdout.write(JSON.stringify(await repository.list(), null, 2) + "\n");
      return;
    }
    if (command === "inspect") {
      process.stdout.write(
        JSON.stringify(await repository.inspect(z.uuid().parse(value)), null, 2) + "\n",
      );
      return;
    }
    const blueprints = await loadGenerationBlueprints(
      fileURLToPath(new URL("../../config/learning/", import.meta.url)),
    );
    if (command === "run") {
      if (!config.learningGenerationEnabled) throw new Error("学习生成开关未开启。");
      const result = await createLearningGenerationProcessor(
        repository,
        blueprints,
        createLearningEditorialCompletion(config),
        config.learningGenerationDailyJobs,
      ).runOnce();
      process.stdout.write(JSON.stringify({ result }) + "\n");
      return;
    }
    const review = z
      .strictObject({
        jobId: z.uuid(),
        candidateHash: z.string().regex(/^[a-f0-9]{64}$/),
        reviewer: z.string().min(2),
        notes: z.string().min(30),
      })
      .parse(JSON.parse(await readFile(value ?? "", "utf8")) as unknown);
    if (command === "reject")
      await repository.reject(
        review.jobId,
        review.candidateHash,
        review.notes,
        review.reviewer,
      );
    else {
      const job = await repository.inspect(review.jobId);
      const blueprint = blueprints.find(
        (b) => b.roleKey === job.role_key && b.level === job.level_key,
      );
      if (!blueprint) throw new Error("当前没有该角色与档位的审核蓝图。");
      await repository.publish(
        review.jobId,
        review.candidateHash,
        blueprint,
        review.reviewer,
        review.notes,
      );
    }
    process.stdout.write(
      JSON.stringify({ result: command, jobId: review.jobId }) + "\n",
    );
  } finally {
    await database.close();
  }
}
void main().catch(() => {
  process.stderr.write("生成或审核操作未完成，请检查配置、任务状态和审核文件。\n");
  process.exitCode = 1;
});
