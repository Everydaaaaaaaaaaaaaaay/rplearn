import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";
import { loadCuratedCatalog } from "./catalog.js";
import { contentHash, unitSchema, type LearningUnit } from "./content.js";
import { answerSchema, gradeAnswer } from "./grading.js";

export const generationPromptVersion = 2;
const manifestSchema = z.strictObject({
  version: z.literal(1),
  roles: z
    .array(
      z.strictObject({
        key: z.string(),
        version: z.number().int().positive(),
        persona: z.string(),
        situations: z.array(z.string()).min(3),
      }),
    )
    .min(1),
  levels: z
    .array(
      z.strictObject({
        key: z.string(),
        blueprintVersion: z.number().int().positive(),
        goalIds: z.array(z.string()).min(1),
        boundaries: z.string(),
        referenceUnitId: z.string(),
        references: unitSchema.shape.references,
      }),
    )
    .min(1),
});
export type GenerationBlueprint = Readonly<{
  roleKey: string;
  level: LearningUnit["level"];
  hash: string;
  roleVersion: number;
  guidance: unknown;
  goalIds: readonly string[];
  references: LearningUnit["references"];
}>;
export async function loadGenerationBlueprints(
  directory: string,
): Promise<readonly GenerationBlueprint[]> {
  const catalog = await loadCuratedCatalog(directory);
  const manifest = manifestSchema.parse(
    JSON.parse(await readFile(join(directory, "generation.json"), "utf8")) as unknown,
  );
  const result: GenerationBlueprint[] = [];
  for (const role of manifest.roles)
    for (const level of manifest.levels) {
      const reference = catalog.units.find(
        (u) => u.id === level.referenceUnitId && u.level === level.key,
      );
      const goals = catalog.registry.goals.filter(
        (g) => level.goalIds.includes(g.id) && g.level === level.key,
      );
      if (!reference || goals.length !== level.goalIds.length)
        throw new Error("生成蓝图缺少已核读的目标或参考单元。");
      const sources = catalog.registry.sources.filter((s) =>
        goals.some((g) => g.sourceIds.includes(s.id)),
      );
      if (
        level.references.some(
          (ref) => !sources.some((source) => source.id === ref.sourceId),
        )
      )
        throw new Error("生成蓝图引用了未登记课程来源。");
      const guidance = {
        role,
        level,
        goals,
        sources,
        referenceLimitations:
          "来源的核读范围与限制必须保留；不得自称精确覆盖整册教材。",
      };
      result.push({
        roleKey: role.key,
        level: reference.level,
        roleVersion: role.version,
        guidance,
        goalIds: level.goalIds,
        references: level.references,
        hash: contentHash({ guidance, references: level.references }),
      });
    }
  if (new Set(result.map((b) => `${b.roleKey}:${b.level}`)).size !== result.length)
    throw new Error("生成蓝图角色与水平不能重复。");
  return result;
}

export const generatedDraftSchema = z.strictObject({
  title: unitSchema.shape.title,
  summary: unitSchema.shape.summary,
  scene: unitSchema.shape.scene,
  goalIds: unitSchema.shape.goalIds.max(2),
  beats: unitSchema.shape.beats.min(3).max(5),
  questions: unitSchema.shape.questions.length(6),
});
export type UnitSummary = Pick<LearningUnit, "id" | "title" | "scene" | "questions">;
export function questionFingerprint(q: LearningUnit["questions"][number]): string {
  return contentHash({
    type: q.type,
    prompt: q.prompt.normalize("NFKC").replace(/\s+/g, "").toLowerCase(),
  });
}
function similar(a: string, b: string): boolean {
  const grams = (s: string) => {
    const chars = Array.from(
      new Intl.Segmenter("en", { granularity: "grapheme" }).segment(
        s.normalize("NFKC").toLowerCase().replace(/\s+/g, ""),
      ),
      (part) => part.segment,
    );
    return new Set(chars.slice(0, -2).map((_, i) => chars.slice(i, i + 3).join("")));
  };
  const x = grams(a),
    y = grams(b);
  if (!x.size || !y.size) return a.trim() === b.trim();
  const intersection = [...x].filter((c) => y.has(c)).length;
  return intersection / (x.size + y.size - intersection) >= 0.82;
}
export function validateGeneratedUnit(
  value: unknown,
  blueprint: GenerationBlueprint,
  existing: readonly UnitSummary[],
): LearningUnit {
  const unit = unitSchema.parse(value);
  if (
    unit.roleKey !== blueprint.roleKey ||
    unit.roleVersion !== blueprint.roleVersion ||
    unit.level !== blueprint.level ||
    unit.version !== 1 ||
    unit.authorship.kind !== "generated" ||
    unit.questions.length !== 6 ||
    unit.goalIds.some((g) => !blueprint.goalIds.includes(g)) ||
    contentHash(unit.references) !== contentHash(blueprint.references)
  )
    throw new Error("生成内容不符合角色、档位或来源蓝图。");
  const previous = existing.flatMap((u) => u.questions);
  const seen: LearningUnit["questions"] = [];
  for (const q of unit.questions) {
    if (
      q.type === "listeningChoice" ||
      q.type === "dictation" ||
      JSON.stringify(q).includes('"imageAssetId"')
    )
      throw new Error("生成资源尚未验收，此批只开放文字题型。");
    if (/看图|图中|图旁|上图|下图/.test([q.prompt, q.instruction, q.hint].join(" ")))
      throw new Error("纯文字题不能指向未提供的图片。");
    if (
      /根据(?:上文|剧情|故事)|刚才|前文|上一题|故事中|in the story|according to the (?:story|passage)/i.test(
        q.prompt,
      )
    )
      throw new Error("题目不能依赖剧情或前题。");
    if (
      [...previous, ...seen].some(
        (old) =>
          questionFingerprint(old) === questionFingerprint(q) ||
          similar(old.prompt, q.prompt),
      )
    )
      throw new Error("生成题目与已有内容重复或过于相似。");
    seen.push(q);
  }
  if (new Set(unit.questions.map((q) => q.type)).size < 3)
    throw new Error("本批单元至少包含三种文字题型。");
  if (
    existing.some(
      (old) => similar(old.title, unit.title) && similar(old.scene, unit.scene),
    )
  )
    throw new Error("生成情境与已有单元过于相似。");
  return unit;
}
export function makeGeneratedUnit(
  content: string,
  blueprint: GenerationBlueprint,
  jobId: string,
): LearningUnit {
  const draft = generatedDraftSchema.parse(JSON.parse(content) as unknown);
  return unitSchema.parse({
    ...draft,
    id: `generated.${jobId}`,
    version: 1,
    schemaVersion: 1,
    scoringVersion: 1,
    roleKey: blueprint.roleKey,
    roleVersion: blueprint.roleVersion,
    level: blueprint.level,
    estimatedMinutes: 6,
    prerequisiteGoalIds: [],
    references: blueprint.references,
    authorship: {
      kind: "generated",
      author: "服务端内容生成",
      reviewedBy: "待逐题复核",
      reviewedAt: new Date().toISOString().slice(0, 10),
      reviewNotes:
        "候选内容，仅通过合同检查尚不可分配；须完成独立审题和首批作者逐题复核。",
    },
  });
}
export const independentReviewSchema = z.strictObject({
  roleFits: z.boolean(),
  levelFits: z.boolean(),
  novel: z.boolean(),
  storyDoesNotLeakAnswers: z.boolean(),
  notes: z.string().min(20).max(3000),
  questions: z
    .array(
      z.strictObject({
        questionId: z.string(),
        independent: z.boolean(),
        unambiguous: z.boolean(),
        grammarCorrect: z.boolean(),
        hintDoesNotReveal: z.boolean(),
        solutionReasonSound: z.boolean(),
        solution: answerSchema,
        incorrectExample: answerSchema,
        reason: z.string().min(15).max(1500),
      }),
    )
    .length(6),
});
export function validateIndependentReview(content: string, unit: LearningUnit) {
  const report = independentReviewSchema.parse(JSON.parse(content) as unknown);
  if (
    !report.roleFits ||
    !report.levelFits ||
    !report.novel ||
    !report.storyDoesNotLeakAnswers ||
    new Set(report.questions.map((q) => q.questionId)).size !== unit.questions.length
  )
    throw new Error("独立审题未通过全局质量条件。");
  for (const question of unit.questions) {
    const check = report.questions.find((q) => q.questionId === question.id);
    if (
      !check ||
      !check.independent ||
      !check.unambiguous ||
      !check.grammarCorrect ||
      !check.hintDoesNotReveal ||
      !check.solutionReasonSound ||
      check.solution.kind === "skip" ||
      check.incorrectExample.kind === "skip" ||
      gradeAnswer(question, check.solution).outcome !== "correct" ||
      gradeAnswer(question, check.incorrectExample).outcome !== "incorrect"
    )
      throw new Error("独立解题或答案反例未通过。");
  }
  return report;
}
