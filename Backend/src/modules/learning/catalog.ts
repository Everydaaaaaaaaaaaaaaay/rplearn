import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";
import {
  contentHash,
  levelSchema,
  unitSchema,
  questionImageIds,
  questionAudios,
  type LearningUnit,
} from "./content.js";
import { answerSchema, gradeAnswer } from "./grading.js";
import { bankIdentity } from "./bank-content.js";
import {
  learningAudioSchema,
  verifyLearningAudio,
  type DeferredLearningAudio,
} from "./audio.js";

import {
  learningImageSchema,
  verifyLearningImage,
  type DeferredLearningImage,
} from "./images.js";

const id = z.string().regex(/^[a-z][a-z0-9_.-]{0,119}$/);
const note = z.string().trim().min(8).max(2000);
const sha256 = z.string().regex(/^[a-f0-9]{64}$/);
const registrySchema = z.strictObject({
  version: z.literal(1),
  audioAssets: z.array(learningAudioSchema).max(5000).optional(),
  imageAssets: z.array(learningImageSchema).max(5000).optional(),
  sources: z
    .array(
      z.strictObject({
        id,
        title: note,
        url: z.url(),
        edition: note,
        readAt: z.iso.date(),
        scope: note,
        limitations: note,
        evidence: z.array(z.strictObject({ locator: note, sha256 })).min(1),
      }),
    )
    .min(1),
  goals: z
    .array(
      z.strictObject({
        id,
        level: levelSchema,
        canDo: note,
        boundaries: note,
        sourceIds: z.array(id).min(1),
      }),
    )
    .min(1),
  unitIds: z.array(id).min(1).max(1000),
});

const reviewSchema = z.strictObject({
  unitId: id,
  contentHash: sha256,
  status: z.literal("approved"),
  reviewKind: z.literal("author-self-review"),
  reviewer: z.string().min(1),
  reviewedAt: z.iso.date(),
  roleFit: note,
  levelFit: note,
  limitations: note,
  questions: z
    .array(
      z.strictObject({
        questionId: id,
        standaloneContext: note,
        ambiguityReview: note,
        imageReview: note.optional(),
        optionNotes: z.record(id, note),
        probes: z
          .array(z.strictObject({ answer: answerSchema, correct: z.boolean() }))
          .min(2),
      }),
    )
    .min(4)
    .max(18),
});

export type CuratedCatalog = Readonly<{
  hash: string;
  registry: z.infer<typeof registrySchema>;
  audioAssets: readonly DeferredLearningAudio[];
  imageAssets: readonly DeferredLearningImage[];
  units: readonly LearningUnit[];
  summary: readonly {
    roleKey: string;
    level: string;
    units: number;
    questions: number;
  }[];
}>;

/** 发布前一次性读取和检查完整目录；不把 JSON 合法冒充教材或教学效果已验证。 */
export async function loadCuratedCatalog(directory: string): Promise<CuratedCatalog> {
  const readJSON = async (path: string): Promise<unknown> =>
    JSON.parse(await readFile(path, "utf8")) as unknown;
  const registry = registrySchema.parse(
    await readJSON(join(directory, "catalog.json")),
  );
  const requireUnique = (values: readonly string[], label: string) => {
    if (new Set(values).size !== values.length) throw new Error(`${label}不能重复。`);
  };
  requireUnique(registry.unitIds, "目录中的单元");
  requireUnique(
    registry.sources.map((s) => s.id),
    "教材来源",
  );
  requireUnique(
    registry.goals.map((g) => g.id),
    "课程目标",
  );
  for (const goal of registry.goals) {
    if (goal.sourceIds.some((source) => !registry.sources.some((s) => s.id === source)))
      throw new Error(`目标 ${goal.id} 引用了未知来源。`);
  }
  const units: LearningUnit[] = [];
  const audioAssets: DeferredLearningAudio[] = [];
  requireUnique(
    (registry.audioAssets ?? []).map((asset) => asset.id),
    "听力资源",
  );
  for (const metadata of registry.audioAssets ?? []) {
    const path = join(directory, "audio", `${metadata.id}.wav`);
    const loadBytes = () => readFile(path);
    verifyLearningAudio(metadata, await loadBytes());
    // 校验时逐个读取；目录不保留媒体字节，上传时再次校验以防文件被替换。
    audioAssets.push({ metadata, loadBytes });
  }
  const imageAssets: DeferredLearningImage[] = [];
  requireUnique(
    (registry.imageAssets ?? []).map((asset) => asset.id),
    "图片资源",
  );
  for (const metadata of registry.imageAssets ?? []) {
    const path = join(directory, "images", `${metadata.id}.png`);
    const loadBytes = () => readFile(path);
    verifyLearningImage(metadata, await loadBytes());
    imageAssets.push({ metadata, loadBytes });
  }
  const reviews: z.infer<typeof reviewSchema>[] = [];
  const fingerprints = new Set<string>();
  for (const unitId of registry.unitIds) {
    const unit = unitSchema.parse(
      await readJSON(join(directory, "units", `${unitId}.json`)),
    );
    const review = reviewSchema.parse(
      await readJSON(join(directory, "reviews", `${unitId}.json`)),
    );
    const fail: (message: string) => never = (message) => {
      throw new Error(`${unitId}：${message}`);
    };
    if (unit.id !== unitId || review.unitId !== unitId)
      fail("目录、单元与审核记录身份不一致。");
    if (review.contentHash !== contentHash(unit))
      fail("内容已变化，需要重新逐题审核。");
    if (
      unit.authorship.kind !== "authored" ||
      !["oliver", "ruby", "marcus", "companion"].includes(unit.roleKey)
    )
      fail("此目录只接收主角色或通用同行者的亲自编写内容；生成内容走独立审核路径。");
    if (
      unit.authorship.reviewedBy !== review.reviewer ||
      unit.authorship.reviewedAt !== review.reviewedAt
    )
      fail("作者信息与审核记录不一致。");
    if (
      unit.references.some(
        (ref) => !registry.sources.some((source) => source.id === ref.sourceId),
      )
    )
      fail("引用了未登记的教材来源。");
    for (const goalId of [...unit.goalIds, ...unit.prerequisiteGoalIds]) {
      const goal = registry.goals.find((g) => g.id === goalId);
      if (!goal || (unit.goalIds.includes(goalId) && goal.level !== unit.level))
        fail(`目标 ${goalId} 不存在或难度档位不符。`);
      if (
        unit.goalIds.includes(goalId) &&
        !goal.sourceIds.some((source) =>
          unit.references.some((ref) => ref.sourceId === source),
        )
      )
        fail(`目标 ${goalId} 缺少本单元的来源依据。`);
    }
    requireUnique(
      review.questions.map((q) => q.questionId),
      "逐题审核记录",
    );
    if (review.questions.length !== unit.questions.length)
      fail("逐题审核没有完整覆盖。");
    for (const question of unit.questions) {
      const checked = review.questions.find((q) => q.questionId === question.id);
      if (!checked) fail(`题目 ${question.id} 缺少审核。`);
      for (const audio of questionAudios(question)) {
        const asset = audioAssets.find(
          (asset) => asset.metadata.id === audio.assetId,
        )?.metadata;
        if (asset?.transcript !== audio.text || asset.voice !== audio.voice)
          fail("听力题缺少已审核音频，或其原文和声音与资源不一致。");
      }
      const images = questionImageIds(question);
      if (
        images.some(
          (imageId) => !imageAssets.some((asset) => asset.metadata.id === imageId),
        )
      )
        fail(`题目 ${question.id} 引用了未审核的图片。`);
      if (images.length > 0 && !checked.imageReview)
        fail(`题目 ${question.id} 缺少图片语义、替代描述及答案泄露审核。`);
      // 目录判重忽略大小写，公共题身份保持原规则，避免改变已发布题目的编号。
      const fingerprint =
        question.type === "cloze"
          ? bankIdentity({
              ...question,
              prompt: question.prompt.toLowerCase(),
              passage: question.passage.toLowerCase(),
              tokens: question.tokens.map((token) => ({
                ...token,
                text: token.text.toLowerCase(),
              })),
            })
          : contentHash({
              type: question.type,
              prompt: question.prompt.trim().toLowerCase(),
              // “听写完整句子”等操作语可以复用，录音原文才是听力题的作答材料。
              ...("audio" in question && question.audio
                ? { audio: question.audio.text.trim().toLowerCase() }
                : {}),
              ...(question.type === "audioChoice" || question.type === "audioMatching"
                ? {
                    audioOptions: question.audioOptions
                      .map((o) => o.audio.text.trim().toLowerCase())
                      .sort(),
                  }
                : {}),
            });
      if (fingerprints.has(fingerprint))
        fail(`题目 ${question.id} 与题库中已有题干重复。`);
      fingerprints.add(fingerprint);
      if (
        !checked.probes.some((p) => p.correct) ||
        !checked.probes.some((p) => !p.correct)
      )
        fail(`题目 ${question.id} 必须同时有正确与错误答案反例。`);
      for (const probe of checked.probes) {
        if (probe.answer.kind === "skip") fail("跳过不能替代错误答案反例。");
        if (
          (gradeAnswer(question, probe.answer).outcome === "correct") !==
          probe.correct
        )
          fail(`题目 ${question.id} 的判题结果不符合审核样例。`);
      }
      if (
        question.type === "choice" ||
        question.type === "listeningChoice" ||
        question.type === "audioChoice"
      ) {
        const options =
          question.type === "audioChoice" ? question.audioOptions : question.options;
        if (
          Object.keys(checked.optionNotes).length !== options.length ||
          options.some((o) => !checked.optionNotes[o.id])
        )
          fail(`题目 ${question.id} 必须解释每个选项的适切性。`);
      } else if (Object.keys(checked.optionNotes).length !== 0) {
        fail(`题目 ${question.id} 包含不适用的选项审核。`);
      }
    }
    units.push(unit);
    reviews.push(review);
  }
  const summary: {
    roleKey: string;
    level: string;
    units: number;
    questions: number;
  }[] = [];
  for (const unit of units) {
    let row = summary.find((r) => r.roleKey === unit.roleKey && r.level === unit.level);
    if (!row) {
      row = { roleKey: unit.roleKey, level: unit.level, units: 0, questions: 0 };
      summary.push(row);
    }
    row.units += 1;
    row.questions += unit.questions.length;
  }
  return {
    registry,
    hash: contentHash({ registry, units, reviews }),
    units,
    audioAssets,
    imageAssets,
    summary,
  };
}
