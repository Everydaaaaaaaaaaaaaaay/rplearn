import { describe, expect, it } from "vitest";
import {
  publicQuestion,
  publicUnit,
  questionAudios,
  unitSchema,
  type LearningQuestion,
} from "../../../src/modules/learning/content.js";
import { gradeAnswer } from "../../../src/modules/learning/grading.js";
import { bankIdentity } from "../../../src/modules/learning/bank-content.js";
import { learningFixture } from "../../helpers/learning.js";

function required<T>(value: T | undefined): T {
  if (value === undefined) throw new Error("缺少测试夹具。");
  return value;
}

// 工程合同夹具，不作为教材题或真实录音发布。
const question: Extract<LearningQuestion, { type: "audioChoice" }> = {
  id: "test.sound",
  type: "audioChoice",
  goalId: "test.greetings",
  instruction: "逐段播放，再选择。",
  prompt: "工程声音选择。",
  hint: "工程提示。",
  explanation: "工程解析。",
  difficultyReason: "仅供独立媒体合同验证。",
  audioOptions: [
    {
      id: "a",
      audio: { assetId: "audio.first", text: "First test recording.", voice: "M3" },
    },
    {
      id: "b",
      audio: { assetId: "audio.second", text: "Second test recording.", voice: "M3" },
    },
  ],
  answer: "b",
};
const unit = (q: unknown) => ({
  ...learningFixture(),
  questions: [q, ...learningFixture().questions.slice(1)],
});
describe("独立声音选项", () => {
  it("同一挑战的声音顺序稳定，多个挑战可采用不同顺序且不修改私有原题", () => {
    const parsed = unitSchema.parse(unit(question));
    const original = structuredClone(parsed);
    const projections = Array.from({ length: 20 }, (_, i) =>
      publicUnit(parsed, `attempt${String(i)}`),
    );
    expect(publicUnit(parsed, "attempt0")).toEqual(projections[0]);
    expect(
      new Set(projections.map((u) => JSON.stringify(u.questions[0]))).size,
    ).toBeGreaterThan(1);
    expect(parsed).toEqual(original);
  });
  it("公开投影只包含不透明素材身份，隐藏全部原文、声线、答案及解析", () => {
    expect(unitSchema.safeParse(unit(question)).success).toBe(true);
    expect(publicQuestion(question)).toEqual({
      id: question.id,
      type: question.type,
      goalId: question.goalId,
      instruction: question.instruction,
      prompt: question.prompt,
      hint: question.hint,
      audioOptions: [
        { id: "a", audio: { assetId: "audio.first" } },
        { id: "b", audio: { assetId: "audio.second" } },
      ],
    });
    expect(questionAudios(question)).toEqual(question.audioOptions.map((o) => o.audio));
  });
  it("按选择身份判整题，拒绝不存在选项及错误作答类型", () => {
    expect(gradeAnswer(question, { kind: "choice", optionId: "b" }).outcome).toBe(
      "correct",
    );
    expect(gradeAnswer(question, { kind: "choice", optionId: "a" }).outcome).toBe(
      "incorrect",
    );
    expect(gradeAnswer(question, { kind: "skip" }).outcome).toBe("skipped");
    expect(() => gradeAnswer(question, { kind: "choice", optionId: "c" })).toThrow();
    expect(() => gradeAnswer(question, { kind: "text", text: "b" })).toThrow();
  });
  it("拒绝重复身份、重复音频和重复听辨内容，答案必须指向声音选项", () => {
    for (const change of [
      { answer: "missing" },
      { audioOptions: [question.audioOptions[0], question.audioOptions[0]] },
      {
        audioOptions: [
          question.audioOptions[0],
          { ...question.audioOptions[0], id: "c" },
        ],
      },
      {
        audioOptions: [
          question.audioOptions[0],
          {
            id: "b",
            audio: {
              ...required(question.audioOptions[0]).audio,
              assetId: "audio.other",
            },
          },
        ],
      },
    ])
      expect(unitSchema.safeParse(unit({ ...question, ...change })).success).toBe(
        false,
      );
  });
  it("换编号、声线或选项顺序不能生成新内容身份；换实际录音语句才改变", () => {
    const renamed = {
      ...question,
      audioOptions: [...question.audioOptions]
        .reverse()
        .map((o, i) => ({
          ...o,
          id: `x${String(i)}`,
          audio: { ...o.audio, voice: "F3" },
        })),
    };
    expect(bankIdentity(renamed)).toBe(bankIdentity(question));
    required(renamed.audioOptions[0]).audio.text = "Different recording.";
    expect(bankIdentity(renamed)).not.toBe(bankIdentity(question));
  });
});
