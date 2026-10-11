import { describe, expect, it } from "vitest";
import {
  publicUnit,
  questionAudios,
  questionImageIds,
  unitSchema,
  type LearningQuestion,
} from "../../../src/modules/learning/content.js";
import { gradeAnswer } from "../../../src/modules/learning/grading.js";
import { bankIdentity } from "../../../src/modules/learning/bank-content.js";
import { learningFixture } from "../../helpers/learning.js";

// 只验证合同，不是可发布教学素材。
const question: Extract<LearningQuestion, { type: "audioMatching" }> = {
  id: "test.audio-matching",
  type: "audioMatching",
  goalId: "test.greetings",
  instruction: "给声音配图",
  prompt: "工程检查",
  hint: "工程提示",
  explanation: "工程解析",
  difficultyReason: "独立声音与图片映射工程测试",
  audioOptions: [
    { id: "s1", audio: { assetId: "audio.one", text: "First audio.", voice: "M3" } },
    { id: "s2", audio: { assetId: "audio.two", text: "Second audio.", voice: "M3" } },
  ],
  right: [
    { id: "r1", text: "图一", imageAssetId: "image.one" },
    { id: "r2", text: "图二", imageAssetId: "image.two", caption: "会" },
    { id: "r3", text: "图二", imageAssetId: "image.two", caption: "不会" },
  ],
  answerPairs: [
    { left: "s1", right: "r2" },
    { left: "s2", right: "r1" },
  ],
};
const unit = (q: unknown) => ({
  ...learningFixture(),
  questions: [q, ...learningFixture().questions.slice(1)],
});
describe("声音配图", () => {
  it("公开隐藏两条原文和映射，图片标签保留，左右显示顺序稳定且互相独立", () => {
    const parsed = unitSchema.parse(unit(question));
    const initial = structuredClone(parsed);
    const visible = publicUnit(parsed, "attempt1");
    expect(publicUnit(parsed, "attempt1")).toEqual(visible);
    expect(visible.questions[0]).not.toHaveProperty("answerPairs");
    expect(JSON.stringify(visible)).not.toContain("First audio.");
    expect(questionAudios(question)).toHaveLength(2);
    expect(questionImageIds(question)).toEqual(["image.one", "image.two"]);
    expect(parsed).toEqual(initial);
    const views = Array.from(
      { length: 20 },
      (_, i) => publicUnit(parsed, `test${String(i)}`).questions[0],
    );
    expect(new Set(views.map((q) => JSON.stringify(q))).size).toBeGreaterThan(2);
  });
  it("多余图片可不使用，全部声音配对正确才得到整题正确；反馈逐映射返回", () => {
    const correct = gradeAnswer(question, {
      kind: "matching",
      pairs: [...question.answerPairs].reverse(),
    });
    expect(correct.outcome).toBe("correct");
    expect(correct.pairResults).toEqual([
      { left: "s1", correct: true },
      { left: "s2", correct: true },
    ]);
    const partial = gradeAnswer(question, {
      kind: "matching",
      pairs: [
        { left: "s1", right: "r2" },
        { left: "s2", right: "r3" },
      ],
    });
    expect(partial.outcome).toBe("incorrect");
    expect(partial.pairResults).toEqual([
      { left: "s1", correct: true },
      { left: "s2", correct: false },
    ]);
    expect(
      gradeAnswer(question, { kind: "skip" }).pairResults?.every((p) => !p.correct),
    ).toBe(true);
    expect(
      gradeAnswer(question, { kind: "matching", pairs: [{ left: "s1", right: "r2" }] })
        .outcome,
    ).toBe("incorrect");
  });
  it("拒绝重复占图、重复声音及越界映射", () => {
    for (const pairs of [
      [
        { left: "s1", right: "r1" },
        { left: "s2", right: "r1" },
      ],
      [
        { left: "s1", right: "r1" },
        { left: "s1", right: "r2" },
      ],
      [{ left: "absent", right: "r1" }],
    ])
      expect(() => gradeAnswer(question, { kind: "matching", pairs })).toThrow();
    expect(() => gradeAnswer(question, { kind: "choice", optionId: "r1" })).toThrow();
  });
  it("合同要求至少一张干扰图、声音全覆盖，不能只有不同无障碍名称的相同视觉选项", () => {
    for (const change of [
      { right: question.right.slice(0, 2) },
      { answerPairs: question.answerPairs.slice(0, 1) },
      {
        right: [
          question.right[0],
          question.right[1],
          { id: "r3", text: "不同名字", imageAssetId: "image.two", caption: "会" },
        ],
      },
      {
        answerPairs: [
          { left: "s1", right: "r2" },
          { left: "s2", right: "absent" },
        ],
      },
    ])
      expect(unitSchema.safeParse(unit({ ...question, ...change })).success).toBe(
        false,
      );
  });
  it("调换声音或图片位置不造新题，改变必要标签才改变题意身份", () => {
    const reordered = {
      ...question,
      audioOptions: [...question.audioOptions].reverse(),
      right: [...question.right].reverse(),
    };
    expect(bankIdentity(reordered)).toBe(bankIdentity(question));
    expect(
      bankIdentity({
        ...question,
        right: question.right.map((o) =>
          o.id === "r2" ? { ...o, caption: "能够" } : o,
        ),
      }),
    ).not.toBe(bankIdentity(question));
  });
});
