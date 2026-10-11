import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";
import { loadCuratedCatalog } from "./catalog.js";
import {
  bankBlueprintSchema,
  bankCatalogRevisionSchema,
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
      revisions: z.array(bankCatalogRevisionSchema).max(1000).optional(),
      units: z.array(
        z.strictObject({
          unitId: z.string(),
          topic: z.enum(bankTags),
          roleKeys: z.array(z.string()),
          questionExclusions: z
            .record(z.string(), bankQuestionSchema.shape.exclusionGroupIds.unwrap())
            .optional(),
        }),
      ),
    })
    .parse(JSON.parse(await readFile(join(directory, "bank.json"), "utf8")));
  if (new Set(manifest.units.map((u) => u.unitId)).size !== manifest.units.length)
    throw new Error("公共题库分类清单含重复单元。");
  const revisions = manifest.revisions ?? [];
  if (new Set(revisions.map((r) => r.question.id)).size !== revisions.length)
    throw new Error("公共题库目录含重复修订身份。");
  const entries = manifest.units.flatMap((rule) => {
    const unit = catalog.units.find((u) => u.id === rule.unitId);
    if (!unit) throw new Error(`公共题库引用未审核单元：${rule.unitId}`);
    for (const questionId of Object.keys(rule.questionExclusions ?? {})) {
      if (!unit.questions.some((q) => q.id === questionId))
        throw new Error(`互斥规则引用了单元中不存在的题目：${questionId}`);
    }
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
        ...(rule.questionExclusions?.[question.id]
          ? { exclusionGroupIds: rule.questionExclusions[question.id] }
          : {}),
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
            estimatedMinutes: unit.estimatedMinutes,
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
    revisions,
    // 无修订的既有目录保持原哈希；新增修订必须纳入发布确认摘要。
    hash: contentHash({
      entries,
      blueprints,
      ...(revisions.length ? { revisions } : {}),
    }),
    catalogHash: catalog.hash,
  };
}
