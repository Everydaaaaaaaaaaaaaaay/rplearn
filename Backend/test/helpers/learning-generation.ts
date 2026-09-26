import { fileURLToPath } from "node:url";
import { loadCuratedCatalog } from "../../src/modules/learning/catalog.js";
import {
  loadGenerationBlueprints,
  makeGeneratedUnit,
} from "../../src/modules/learning/generation-content.js";
import {
  gradeAnswer,
  type LearningAnswer,
} from "../../src/modules/learning/grading.js";
import type { LearningUnit } from "../../src/modules/learning/content.js";

/** 复用已知内容仅验证生成协议，绝不能将此夹具发布到公共题库。 */
export async function generationFixture(jobId: string) {
  const directory = fileURLToPath(new URL("../../config/learning/", import.meta.url));
  const catalog = await loadCuratedCatalog(directory);
  const blueprint = (await loadGenerationBlueprints(directory)).find(
    (b) => b.roleKey === "oliver",
  );
  const sample = catalog.units.find((u) => u.id === "oliver.primary3.colour-covers");
  if (!blueprint || !sample) throw new Error("缺少工程测试来源。");
  const draft = JSON.stringify({
    title: sample.title,
    summary: sample.summary,
    scene: sample.scene,
    goalIds: sample.goalIds,
    beats: sample.beats,
    questions: sample.questions,
  });
  const unit = makeGeneratedUnit(draft, blueprint, jobId);
  return { blueprint, draft, unit, report: reviewFixture(unit) };
}
export function reviewFixture(unit: LearningUnit) {
  return {
    roleFits: true,
    levelFits: true,
    novel: true,
    storyDoesNotLeakAnswers: true,
    notes: "仅供事务与合同检查的工程审核夹具，不作为真实内容质量证明。",
    questions: unit.questions.map((q) => {
      const solution = gradeAnswer(q, { kind: "skip" }).solution;
      let incorrectExample: LearningAnswer;
      switch (solution.kind) {
        case "choice":
          incorrectExample = {
            kind: "choice",
            optionId:
              (q.type === "choice" || q.type === "listeningChoice"
                ? q.options.find((o) => o.id !== solution.optionId)?.id
                : undefined) ?? "wrong",
          };
          break;
        case "arrange":
          incorrectExample = {
            kind: "arrange",
            tokenIds: [...solution.tokenIds].reverse(),
          };
          break;
        case "matching":
          incorrectExample = {
            kind: "matching",
            pairs: solution.pairs.map((p, i) => ({
              left: p.left,
              right: solution.pairs[(i + 1) % solution.pairs.length]?.right ?? p.right,
            })),
          };
          break;
        default:
          incorrectExample = { kind: "text", text: "not an answer" };
      }
      return {
        questionId: q.id,
        independent: true,
        unambiguous: true,
        grammarCorrect: true,
        hintDoesNotReveal: true,
        solutionReasonSound: true,
        solution,
        incorrectExample,
        reason: "仅用于验证答案与反例检查的固定工程数据。",
      };
    }),
  };
}
