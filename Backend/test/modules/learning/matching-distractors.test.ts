import { describe, expect, it } from "vitest";
import {
  unitSchema,
  type LearningQuestion,
} from "../../../src/modules/learning/content.js";
import { gradeAnswer } from "../../../src/modules/learning/grading.js";
import { learningFixture } from "../../helpers/learning.js";

describe("文字配对保留干扰项", () => {
  const question: Extract<LearningQuestion, { type: "matching" }> = {
    id: "test.matching-extra",
    goalId: "test.greetings",
    type: "matching",
    instruction: "工程配对",
    prompt: "工程检查",
    hint: "工程提示",
    explanation: "工程解析",
    difficultyReason: "检查多余候选与完整配对边界",
    left: [
      { id: "a", text: "第一项" },
      { id: "b", text: "第二项" },
    ],
    right: [
      { id: "x", text: "候选一" },
      { id: "y", text: "候选二" },
      { id: "z", text: "干扰项" },
    ],
    answerPairs: [
      { left: "a", right: "x" },
      { left: "b", right: "y" },
    ],
  };
  const unit = (q: typeof question) => ({
    ...learningFixture(),
    questions: [q, ...learningFixture().questions.slice(1)],
  });
  it("允许多余右项，保留既有等长配对，不需要把干扰项也配完", () => {
    expect(unitSchema.safeParse(unit(question)).success).toBe(true);
    expect(
      unitSchema.safeParse(unit({ ...question, right: question.right.slice(0, 2) }))
        .success,
    ).toBe(true);
    expect(
      gradeAnswer(question, { kind: "matching", pairs: question.answerPairs }).outcome,
    ).toBe("correct");
  });
  it("不自动填入剩余答案，也不把干扰项当作可接受答案", () => {
    expect(
      gradeAnswer(question, {
        kind: "matching",
        pairs: question.answerPairs.slice(0, 1),
      }).outcome,
    ).toBe("incorrect");
    expect(
      gradeAnswer(question, {
        kind: "matching",
        pairs: [
          { left: "a", right: "x" },
          { left: "b", right: "z" },
        ],
      }).outcome,
    ).toBe("incorrect");
  });
  it("仍拒绝遗漏左项、重复占用及不存在的正确候选", () => {
    expect(
      unitSchema.safeParse(
        unit({ ...question, answerPairs: question.answerPairs.slice(0, 1) }),
      ).success,
    ).toBe(false);
    expect(
      unitSchema.safeParse(
        unit({
          ...question,
          answerPairs: [
            { left: "a", right: "x" },
            { left: "b", right: "x" },
          ],
        }),
      ).success,
    ).toBe(false);
    expect(
      unitSchema.safeParse(
        unit({
          ...question,
          answerPairs: [
            { left: "a", right: "x" },
            { left: "b", right: "missing" },
          ],
        }),
      ).success,
    ).toBe(false);
  });
});
