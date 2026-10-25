import { readFile } from "node:fs/promises";
import { contentHash } from "./content.js";
import { seniorPracticeCatalog } from "./senior-practice-catalog.js";
import { learningImageSchema, verifyLearningImage } from "./images.js";
import { gradeAnswer } from "./grading.js";
import { hasAppropriateQuestionLanguage } from "./presentation.js";

export async function loadGaokaoCatalog() {
  const catalog = seniorPracticeCatalog();
  const directory = new URL("../../../config/learning/gaokao/", import.meta.url);
  const metadata = learningImageSchema.parse(
    JSON.parse(await readFile(new URL("image.json", directory), "utf8")),
  );
  const bytes = await readFile(
    new URL("2025-national1-transport-chart.png", directory),
  );
  verifyLearningImage(metadata, bytes);
  for (const { unit } of catalog.practices)
    for (const q of unit.questions) {
      if (!hasAppropriateQuestionLanguage(q, unit.level))
        throw new Error("高考题干或候选语言不符。");
      for (const image of q.materialImages ?? [])
        if (image.assetId !== metadata.id) throw new Error("高考必要图表未核验。");
      if (q.type === "completion" && q.marking)
        for (const text of q.marking.rejectedAnswers) {
          if (gradeAnswer(q, { kind: "text", text }).outcome !== "incorrect")
            throw new Error("原创填空反证回填失败。");
        }
      if (q.type === "choice")
        for (const option of q.options) {
          if (
            (gradeAnswer(q, { kind: "choice", optionId: option.id }).outcome ===
              "correct") !==
            (option.id === q.answer)
          )
            throw new Error("高考选择题逐项判分失败。");
        }
      else if (q.type === "completion")
        for (const text of q.acceptedAnswers) {
          if (gradeAnswer(q, { kind: "text", text }).outcome !== "correct")
            throw new Error("高考填空参考答案回填失败。");
        }
    }
  return {
    hash: contentHash(
      catalog.practices.map((p) => ({
        id: p.unit.id,
        contentHash: p.contentHash,
        components: p.components,
      })),
    ),
    units: catalog.practices.map((p) => p.unit),
    imageAssets: [{ metadata, bytes }],
  };
}
