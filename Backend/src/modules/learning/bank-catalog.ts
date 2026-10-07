import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";
import { loadCuratedCatalog } from "./catalog.js";
import {
  bankBlueprintSchema,
  bankIdentity,
  bankQuestionSchema,
  bankTags,
} from "./bank-content.js";
import { contentHash } from "./content.js";

/** 分类清单和逐题审核哈希同时成立才导入，不从未审核的模型候选抽题。 */
export async function loadBankCatalog(directory: string) {
  const catalog = await loadCuratedCatalog(directory);
  const manifest = z
    .strictObject({
      version: z.literal(1),
      reviewNotes: z.string().min(30),
      units: z.array(
        z.strictObject({
          unitId: z.string(),
          topic: z.enum(bankTags),
          roleKeys: z.array(z.string()),
        }),
      ),
    })
    .parse(JSON.parse(await readFile(join(directory, "bank.json"), "utf8")));
  if (new Set(manifest.units.map((u) => u.unitId)).size !== manifest.units.length)
    throw new Error("公共题库分类清单含重复单元。");
  const entries = manifest.units.flatMap((rule) => {
    const unit = catalog.units.find((u) => u.id === rule.unitId);
    if (!unit) throw new Error(`公共题库引用未审核单元：${rule.unitId}`);
    return unit.questions.map((question) => ({
      unitId: unit.id,
      unitVersion: unit.version,
      localQuestionId: question.id,
      question: bankQuestionSchema.parse({
        id: bankIdentity(question),
        version: 1,
        level: unit.level,
        topic: rule.topic,
        roleKeys: rule.roleKeys,
        question,
        references: unit.references,
        reviewNotes: manifest.reviewNotes,
      }),
    }));
  });
  const blueprints = manifest.units.map((rule) => {
    const unit = catalog.units.find((u) => u.id === rule.unitId);
    if (!unit) throw new Error("组卷规则引用了不存在的单元。");
    return bankBlueprintSchema.parse({
      id: `bank.${unit.id}`,
      title: unit.title,
      level: unit.level,
      topic: rule.topic,
      prerequisiteGoalIds: unit.prerequisiteGoalIds,
      // 完整故事与抽出的题目独立；不能把只有首镜头的旧单元误当完整开场。
      ...(unit.beats.every((beat) => beat.afterQuestion === 0)
        ? {
            openingStory: {
              title: unit.summary,
              scene: unit.scene,
              beats: unit.beats,
            },
          }
        : {}),
      slots: unit.questions.map((q) => ({ goalId: q.goalId, type: q.type })),
    });
  });
  return {
    entries,
    blueprints,
    hash: contentHash({ entries, blueprints }),
    catalogHash: catalog.hash,
  };
}
