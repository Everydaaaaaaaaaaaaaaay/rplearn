import { describe, expect, it } from "vitest";
import {
  publicQuestion,
  unitSchema,
  type LearningQuestion,
} from "../../../src/modules/learning/content.js";
import { answerSchema, gradeAnswer } from "../../../src/modules/learning/grading.js";
import { bankIdentity } from "../../../src/modules/learning/bank-content.js";
import { reviewSchemaForUnit } from "../../../src/modules/learning/generation-content.js";
import { learningFixture } from "../../helpers/learning.js";

// 仅验证空位、共享词库和完整组合的工程夹具，不是教学题目。
const question: Extract<LearningQuestion, { type: "cloze" }> = {
  id: "test.cloze",
  type: "cloze",
  goalId: "test.greetings",
  instruction: "填两空。",
  prompt: "工程检查。",
  hint: "工程提示。",
  explanation: "工程解析。",
  difficultyReason: "仅供合同测试。",
  passage: "A {first}.\nB {second}.",
  tokens: [
    { id: "x", text: "X" },
    { id: "y", text: "Y" },
    { id: "z", text: "Z" },
  ],
  acceptedFills: [
    [
      { slotId: "first", tokenId: "x" },
      { slotId: "second", tokenId: "y" },
    ],
  ],
};
const unit = (q: unknown = question) => ({
  ...learningFixture(),
  questions: [q, ...learningFixture().questions.slice(1)],
});
describe("多空共享词库合同与判题", () => {
  it("公开原句和全部词块，答案组合与逐空判定不提前泄漏", () => {
    expect(unitSchema.safeParse(unit()).success).toBe(true);
    const visible = publicQuestion(question);
    expect(visible).toHaveProperty("passage", question.passage);
    expect(visible).toHaveProperty("tokens", question.tokens);
    expect(visible).not.toHaveProperty("acceptedFills");
    expect(visible).not.toHaveProperty("slotResults");
    expect(visible).not.toHaveProperty("explanation");
    expect(() => reviewSchemaForUnit(unitSchema.parse(unit()))).not.toThrow();
  });
  it("按空位身份判整题，支持任意提交顺序，部分正确只提供反馈", () => {
    const result = gradeAnswer(question, {
      kind: "cloze",
      fills: [...(question.acceptedFills[0] ?? [])].reverse(),
    });
    expect(result.outcome).toBe("correct");
    expect(result.slotResults?.every((slot) => slot.correct)).toBe(true);
    const partial = gradeAnswer(question, {
      kind: "cloze",
      fills: [
        { slotId: "first", tokenId: "x" },
        { slotId: "second", tokenId: "z" },
      ],
    });
    expect(partial.outcome).toBe("incorrect");
    expect(partial.slotResults).toEqual([
      { slotId: "first", correct: true },
      { slotId: "second", correct: false },
    ]);
    expect(
      gradeAnswer(question, {
        kind: "cloze",
        fills: [{ slotId: "first", tokenId: "x" }],
      }).outcome,
    ).toBe("incorrect");
    expect(gradeAnswer(question, { kind: "skip" }).outcome).toBe("skipped");
  });
  it("拒绝未知空位、未知词、重复使用和错误提交题型", () => {
    for (const fills of [
      [{ slotId: "other", tokenId: "x" }],
      [{ slotId: "first", tokenId: "other" }],
      [
        { slotId: "first", tokenId: "x" },
        { slotId: "second", tokenId: "x" },
      ],
      [
        { slotId: "first", tokenId: "x" },
        { slotId: "first", tokenId: "y" },
      ],
    ])
      expect(() => gradeAnswer(question, { kind: "cloze", fills })).toThrow();
    expect(() => gradeAnswer(question, { kind: "text", text: "X Y" })).toThrow();
    expect(
      answerSchema.safeParse({ kind: "cloze", fills: [], points: 1 }).success,
    ).toBe(false);
  });
  it("多个合法组合不会被拆散拼出第三个答案，反馈采用同一个合法组合", () => {
    const variants = {
      ...question,
      acceptedFills: [
        ...question.acceptedFills,
        [
          { slotId: "first", tokenId: "y" },
          { slotId: "second", tokenId: "z" },
        ],
      ],
    };
    const accepted = gradeAnswer(variants, {
      kind: "cloze",
      fills: variants.acceptedFills[1] ?? [],
    });
    expect(accepted.outcome).toBe("correct");
    expect(accepted.solution).toEqual({
      kind: "cloze",
      fills: variants.acceptedFills[1],
    });
    expect(
      gradeAnswer(variants, {
        kind: "cloze",
        fills: [
          { slotId: "first", tokenId: "x" },
          { slotId: "second", tokenId: "z" },
        ],
      }).outcome,
    ).toBe("incorrect");
  });
  it("发布拒绝破损标记、单空、重复词块、错误身份和不完整组合", () => {
    for (const changes of [
      { passage: "A {first} B {first}" },
      { passage: "A {first}" },
      { passage: "A {first} B {second} {坏空位}" },
      {
        tokens: [
          { id: "x", text: "X" },
          { id: "y", text: "x" },
        ],
      },
      {
        tokens: question.tokens.map((token) => ({
          ...token,
          imageAssetId: "image.test",
        })),
      },
      {
        acceptedFills: [
          [
            { slotId: "first", tokenId: "x" },
            { slotId: "second", tokenId: "x" },
          ],
        ],
      },
      {
        acceptedFills: [
          [
            { slotId: "first", tokenId: "x" },
            { slotId: "other", tokenId: "y" },
          ],
        ],
      },
      {
        acceptedFills: [
          [
            { slotId: "first", tokenId: "x" },
            { slotId: "second", tokenId: "other" },
          ],
        ],
      },
    ])
      expect(unitSchema.safeParse(unit({ ...question, ...changes })).success).toBe(
        false,
      );
  });
  it("改空位与词块编号不制造新题，原文或词库不同才改变材料身份", () => {
    expect(
      bankIdentity({
        ...question,
        passage: "A {a}.\nB {b}.",
        tokens: question.tokens.map((token) => ({ ...token, id: `new.${token.id}` })),
      }),
    ).toBe(bankIdentity(question));
    expect(bankIdentity({ ...question, passage: "C {first}.\nB {second}." })).not.toBe(
      bankIdentity(question),
    );
    expect(
      bankIdentity({
        ...question,
        tokens: [...question.tokens, { id: "extra", text: "extra" }],
      }),
    ).not.toBe(bankIdentity(question));
  });
});
