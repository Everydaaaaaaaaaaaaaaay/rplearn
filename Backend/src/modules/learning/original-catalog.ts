import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { z } from "zod";
import {
  contentHash,
  unitSchema,
  questionAudios,
  questionImageIds,
} from "./content.js";
import { answerSchema, gradeAnswer } from "./grading.js";
import { learningAudioSchema, verifyLearningAudioFile } from "./audio.js";
import { learningImageSchema, verifyLearningImage } from "./images.js";

const manifestSchema = z.strictObject({
  version: z.literal(1),
  researchPlanSHA256: z.string().regex(/^[a-f0-9]{64}$/),
  scopeSHA256: z.string().regex(/^[a-f0-9]{64}$/),
  reviewBoundary: z.string().min(30),
  units: z
    .array(
      z.strictObject({
        unit: unitSchema,
        contentHash: z.string(),
        authoredPayloadSHA256: z.string().regex(/^[a-f0-9]{64}$/),
        studentInputHash: z.string().regex(/^[a-f0-9]{64}$/),
        probes: z
          .array(
            z.strictObject({
              questionId: z.string(),
              answer: answerSchema,
              outcome: z.enum(["correct", "incorrect"]),
            }),
          )
          .min(2),
      }),
    )
    .min(1)
    .max(1000),
  audioAssets: z.array(learningAudioSchema),
  imageAssets: z.array(learningImageSchema),
  batches: z.array(
    z.strictObject({
      id: z.string().regex(/^b[0-9]{3}$/),
      unitIds: z.array(z.string()),
    }),
  ),
});

const rawManifestSchema = z
  .object({
    units: z.array(z.object({ unit: z.object({ id: z.string() }).loose() }).loose()),
    audioAssets: z.array(z.object({ id: z.string() }).loose()),
    imageAssets: z.array(z.object({ id: z.string() }).loose()),
    batches: manifestSchema.shape.batches,
  })
  .loose();

function parseManifest(value: unknown, batchID?: string) {
  const raw = rawManifestSchema.parse(value);
  if (batchID) {
    const ids: string[] | undefined = raw.batches.find(
      (b: { id: string }) => b.id === batchID,
    )?.unitIds;
    if (!ids) throw new Error("未知原创发布批次。");
    raw.units = raw.units.filter((e: { unit: { id: string } }) =>
      ids.includes(e.unit.id),
    );
    if (raw.units.length !== ids.length)
      throw new Error("原创批次引用的完整单元不齐。");
    const units = raw.units.map((e: { unit: unknown }) => unitSchema.parse(e.unit));
    const audios = new Set(
      units.flatMap((u: z.infer<typeof unitSchema>) =>
        u.questions.flatMap(questionAudios).map((a) => a.assetId),
      ),
    );
    const images = new Set(
      units.flatMap((u: z.infer<typeof unitSchema>) =>
        u.questions.flatMap(questionImageIds),
      ),
    );
    raw.audioAssets = raw.audioAssets.filter((a: { id: string }) => audios.has(a.id));
    raw.imageAssets = raw.imageAssets.filter((a: { id: string }) => images.has(a.id));
    raw.batches = raw.batches.filter((b: { id: string }) => b.id === batchID);
  }
  return manifestSchema.parse(raw);
}

/** 冻结作者稿的完整组直接发布，不经过独立题抽取器；媒体先核验再入同一事务。 */
export async function loadOriginalCatalog(directory: string, batchID?: string) {
  const manifest = parseManifest(
    JSON.parse(
      await readFile(join(directory, "originals/catalog.json"), "utf8"),
    ) as unknown,
    batchID,
  );
  const mediaRoot =
    process.env.NODE_ENV === "production"
      ? "/opt/lingotrip/shared/learning-originals-media"
      : join(directory, "originals/media");
  const seen = new Set<string>();
  for (const entry of manifest.units) {
    const unit = entry.unit;
    if (
      !unit.originalGroup ||
      unit.roleKey !== "companion" ||
      unit.authorship.kind !== "authored" ||
      seen.has(unit.id) ||
      contentHash(unit) !== entry.contentHash
    )
      throw new Error(`完整原创单元身份或审核摘要不符：${unit.id}`);
    seen.add(unit.id);
    const student = {
      material: unit.originalGroup.material,
      questions: unit.questions.map((q) => ({
        id: q.id,
        type: q.type,
        prompt: q.prompt,
        instruction: q.instruction,
        options: q.type === "choice" || q.type === "listeningChoice" ? q.options : null,
        audio: "audio" in q && q.audio ? q.audio.assetId : null,
        images: q.materialImages ?? [],
      })),
    };
    if (contentHash(student) !== entry.studentInputHash)
      throw new Error(`完整学生输入与冻结审核不符：${unit.id}`);
    for (const q of unit.questions) {
      const probes = entry.probes.filter((p) => p.questionId === q.id);
      if (
        !probes.some((p) => p.outcome === "correct") ||
        !probes.some((p) => p.outcome === "incorrect")
      )
        throw new Error("逐回应作者判分样例不全。");
      for (const p of probes)
        if (gradeAnswer(q, p.answer).outcome !== p.outcome)
          throw new Error(`作者判分样例不符：${unit.id}/${q.id}`);
    }
    for (const q of unit.questions) {
      if (
        q.type !== "choice" &&
        q.type !== "completion" &&
        q.type !== "listeningChoice"
      )
        throw new Error("未实现的完整组交互不能发布。");
      if (q.type === "completion") {
        if (!q.marking) throw new Error("原创填空缺判分协议。");
        for (const text of q.acceptedAnswers)
          if (gradeAnswer(q, { kind: "text", text }).outcome !== "correct")
            throw new Error("合法变体回填失败。");
        for (const text of q.marking.rejectedAnswers)
          if (gradeAnswer(q, { kind: "text", text }).outcome !== "incorrect")
            throw new Error("错项反证失败。");
      } else {
        for (const option of q.options)
          if (
            (gradeAnswer(q, { kind: "choice", optionId: option.id }).outcome ===
              "correct") !==
            (option.id === q.answer)
          )
            throw new Error("选择题逐项判分不符。");
      }
      for (const audio of questionAudios(q))
        if (
          !manifest.audioAssets.some(
            (a) =>
              a.id === audio.assetId &&
              a.transcript === audio.text &&
              a.voice === audio.voice,
          )
        )
          throw new Error("缺少完整音轨或脚本审核绑定。");
      for (const id of questionImageIds(q))
        if (!manifest.imageAssets.some((a) => a.id === id))
          throw new Error("缺少完整图形输入。");
    }
  }
  const audioAssets = manifest.audioAssets.map((metadata) => ({
    metadata,
    filePath: join(mediaRoot, `${metadata.id}.wav`),
    loadBytes: () => readFile(join(mediaRoot, `${metadata.id}.wav`)),
  }));
  const imageAssets = manifest.imageAssets.map((metadata) => ({
    metadata,
    loadBytes: () => readFile(join(mediaRoot, `${metadata.id}.png`)),
  }));
  for (const asset of audioAssets)
    await verifyLearningAudioFile(asset.metadata, asset.filePath);
  for (const asset of imageAssets)
    verifyLearningImage(asset.metadata, await asset.loadBytes());
  return {
    hash: contentHash(manifest),
    units: manifest.units.map((e) => e.unit),
    audioAssets,
    imageAssets,
  };
}
