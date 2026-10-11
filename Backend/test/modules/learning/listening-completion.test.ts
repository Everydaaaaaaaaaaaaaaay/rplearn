import { describe, expect, it } from "vitest";
import {
  listeningAnswerWordCount,
  publicQuestion,
  questionAudios,
  questionSchema,
  unitSchema,
  type LearningQuestion,
} from "../../../src/modules/learning/content.js";
import { gradeAnswer } from "../../../src/modules/learning/grading.js";
import {
  bankBlueprintSchema,
  bankQuestionSchema,
} from "../../../src/modules/learning/bank-content.js";
import {
  generatedDraftSchema,
  reviewSchemaForUnit,
} from "../../../src/modules/learning/generation-content.js";
import { learningFixture } from "../../helpers/learning.js";

// 仅供合同验证的工程夹具，不进入教学题库。
const question: Extract<LearningQuestion, { type: "listeningCompletion" }> = {
  id: "test.listening-completion",
  type: "listeningCompletion",
  goalId: "test.greetings",
  instruction: "从音频提取不超过两个词。",
  prompt: "工程笔记：目标为____。",
  hint: "工程提示。",
  explanation: "工程解析。",
  difficultyReason: "仅供合同测试。",
  audio: {
    assetId: "test.audio",
    voice: "test",
    text: "The target is alpha beta, not gamma.",
  },
  acceptedAnswers: ["alpha beta", "alpha-beta"],
  normalization: { ignoreCase: true, ignoreTerminalPunctuation: true },
  wordLimit: 2,
};
const unit = () =>
  unitSchema.parse({
    ...learningFixture(),
    questions: [question, ...learningFixture().questions.slice(1)],
  });
const grade = (text: string) => gradeAnswer(question, { kind: "text", text }).outcome;

describe("听力限定词数短答", () => {
  it("接受明确变体与规范化，不把干扰项或全文听写当作短答", () => {
    for (const text of [
      "alpha beta",
      " ALPHA   BETA! ",
      "alpha-beta",
      "alpha\n\tbeta",
      "\uFEFFalpha\u00A0beta\uFEFF",
    ])
      expect(grade(text)).toBe("correct");
    for (const text of [
      "gamma",
      "alpha",
      "alpha betas",
      question.audio.text,
      "alpha beta gamma",
      "",
      "alpha\u200Bbeta",
    ])
      expect(grade(text)).toBe("incorrect");
    expect(gradeAnswer(question, { kind: "skip" }).outcome).toBe("skipped");
    expect(() =>
      gradeAnswer(question, { kind: "choice", optionId: "alpha" }),
    ).toThrow();
  });

  it("词数规则跨端固定，连字符和撇号保留，零宽非空白不作为分隔", () => {
    expect(listeningAnswerWordCount("\uFEFFalpha\u00A0beta\n gamma\uFEFF")).toBe(3);
    expect(listeningAnswerWordCount("alpha-beta can't")).toBe(2);
    expect(listeningAnswerWordCount("alpha\u200Bbeta")).toBe(1);
    expect(listeningAnswerWordCount("\n\u00A0\uFEFF")).toBe(0);
    for (const separator of [
      "\u0009",
      "\u000A",
      "\u000B",
      "\u000C",
      "\u000D",
      " ",
      "\u00A0",
      "\u1680",
      "\u2000",
      "\u200A",
      "\u2028",
      "\u2029",
      "\u202F",
      "\u205F",
      "\u3000",
      "\uFEFF",
    ])
      expect(listeningAnswerWordCount(`alpha${separator}beta`)).toBe(2);
    // 即使末尾标点规范化会移除它，原始提交的第三个片段仍超过限制。
    expect(grade("alpha beta !")).toBe("incorrect");
  });

  it("公开投影仅增加媒体身份与词限，复用媒体集合及独立审题合同", () => {
    expect(publicQuestion(question)).toEqual({
      id: question.id,
      type: question.type,
      goalId: question.goalId,
      instruction: question.instruction,
      prompt: question.prompt,
      hint: question.hint,
      audio: { assetId: question.audio.assetId },
      wordLimit: 2,
    });
    expect(questionAudios(question)).toEqual([question.audio]);
    expect(() => reviewSchemaForUnit(unit())).not.toThrow();
  });

  it("拒绝超限作者答案、缺失媒体、无效词限及未知字段", () => {
    for (const changes of [
      { wordLimit: 0 },
      { wordLimit: 9 },
      { wordLimit: 1.5 },
      { wordLimit: undefined },
      { acceptedAnswers: [] },
      { acceptedAnswers: ["alpha beta gamma"] },
      { acceptedAnswers: ["alpha\u00A0beta\uFEFFgamma"] },
      { audio: undefined },
      { audio: { ...question.audio, assetId: null } },
      { audio: { ...question.audio, text: "" } },
      { answer: "alpha" },
    ])
      expect(questionSchema.safeParse({ ...question, ...changes }).success).toBe(false);
    expect(
      questionSchema.safeParse({
        ...question,
        wordLimit: 1,
        acceptedAnswers: ["alpha-beta", "can't", "alpha\u200Bbeta"],
      }).success,
    ).toBe(true);
  });

  it("题库合同接受新题型，未配置媒体的生成合同仍拒绝该类型", () => {
    const fixture = unit();
    expect(
      bankQuestionSchema.safeParse({
        id: "test.bank",
        version: 1,
        level: fixture.level,
        topic: "daily",
        roleKeys: [],
        question,
        references: fixture.references,
        reviewNotes:
          "工程合同验证记录，确认媒体身份、短答变体、词数限制和发布边界均由明确字段描述。",
      }).success,
    ).toBe(true);
    expect(
      bankBlueprintSchema.safeParse({
        id: "test.blueprint",
        title: "工程蓝图",
        level: fixture.level,
        topic: "daily",
        prerequisiteGoalIds: [],
        slots: Array.from({ length: 6 }, () => ({
          goalId: question.goalId,
          type: question.type,
        })),
      }).success,
    ).toBe(true);
    expect(
      generatedDraftSchema.shape.questions.element.safeParse(question).success,
    ).toBe(false);
  });
});
