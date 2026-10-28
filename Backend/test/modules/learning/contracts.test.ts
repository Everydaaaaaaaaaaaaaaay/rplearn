import { describe, expect, it } from "vitest";
import {
  contentHash,
  publicUnit,
  unitSchema,
} from "../../../src/modules/learning/content.js";
import { answerSchema, gradeAnswer } from "../../../src/modules/learning/grading.js";
import {
  countChatCharacters,
  levelProgress,
  promotionEligibility,
} from "../../../src/modules/learning/policy.js";
import { learningFixture } from "../../helpers/learning.js";

describe("单元内容合同", () => {
  it("十八题可各自引用教学目标，超额题目和空挂目标仍拒绝", () => {
    const unit = learningFixture();
    const seed = unit.questions[0];
    if (!seed) throw new Error("缺少长卷夹具。");
    const questions = Array.from({ length: 18 }, (_, index) => ({
      ...seed,
      id: `test.q${String(index)}`,
      goalId: `test.g${String(index)}`,
    }));
    const longUnit = unitSchema.parse({
      ...unit,
      questions,
      goalIds: [...new Set(questions.map((q) => q.goalId))],
    });
    expect(publicUnit(longUnit).questions).toHaveLength(18);
    expect(publicUnit(longUnit).goalIds).toHaveLength(18);
    expect(
      unitSchema.safeParse({
        ...longUnit,
        questions: questions.slice(0, 17),
      }).success,
    ).toBe(false);
    expect(
      unitSchema.safeParse({
        ...longUnit,
        goalIds: [...longUnit.goalIds, "test.extra"],
      }).success,
    ).toBe(false);
    expect(
      unitSchema.safeParse({
        ...longUnit,
        questions: [...questions, { ...seed, id: "test.extra" }],
      }).success,
    ).toBe(false);
  });
  it("听后排序隐藏原文和答案，并严格验证卡片及录音引用", () => {
    const unit = learningFixture();
    const seed = unit.questions[2];
    if (!seed) throw new Error("缺少排序夹具。");
    if (seed.type !== "arrange") throw new Error("缺少排序夹具。");
    const question = {
      ...seed,
      type: "audioArrange" as const,
      audio: { assetId: "test.order", text: "I am Oliver.", voice: "M5" },
    };
    const parsed = unitSchema.parse({
      ...unit,
      questions: [question, ...unit.questions.filter((q) => q.id !== seed.id)],
    });
    expect(publicUnit(parsed).questions[0]).toEqual({
      id: question.id,
      type: "audioArrange",
      goalId: question.goalId,
      instruction: question.instruction,
      prompt: question.prompt,
      hint: question.hint,
      tokens: question.tokens,
      audio: { assetId: "test.order" },
    });
    const replace = (q: unknown) => ({
      ...unit,
      questions: [q, ...unit.questions.slice(1)],
    });
    expect(
      unitSchema.safeParse(replace({ ...question, id: "test.order", audio: undefined }))
        .success,
    ).toBe(false);
    expect(
      unitSchema.safeParse(
        replace({ ...question, id: "test.order", acceptedOrders: [["i", "missing"]] }),
      ).success,
    ).toBe(false);
    expect(
      unitSchema.safeParse(
        replace({
          ...question,
          id: "test.order",
          tokens: question.tokens.map((t) => ({
            ...t,
            imageAssetId: "image.unsupported",
          })),
        }),
      ).success,
    ).toBe(false);
    expect(
      gradeAnswer(question, { kind: "arrange", tokenIds: ["i", "am", "name"] }).outcome,
    ).toBe("correct");
    expect(
      gradeAnswer(question, { kind: "arrange", tokenIds: ["name", "am", "i"] }).outcome,
    ).toBe("incorrect");
    expect(
      gradeAnswer(question, { kind: "arrange", tokenIds: ["i", "am"] }).outcome,
    ).toBe("incorrect");
    expect(() =>
      gradeAnswer(question, { kind: "arrange", tokenIds: ["i", "i"] }),
    ).toThrow();
    expect(() =>
      gradeAnswer(question, { kind: "arrange", tokenIds: ["i", "foreign"] }),
    ).toThrow();
    expect(() =>
      gradeAnswer(question, { kind: "text", text: "I am Oliver" }),
    ).toThrow();
  });
  it("听后选词保留竞争词块，允许只选录音需要的子集", () => {
    const unit = learningFixture();
    const seed = unit.questions[2];
    if (seed?.type !== "arrange") throw new Error("缺少排序夹具。");
    const question = {
      ...seed,
      type: "audioArrange" as const,
      instruction: "选出听到的词块，有多余词块。",
      tokens: [...seed.tokens, { id: "other", text: "Nina." }],
      audio: { assetId: "test.competition", text: "I am Oliver.", voice: "M5" },
    };
    const parsed = unitSchema.parse({
      ...unit,
      questions: unit.questions.map((q) => (q.id === seed.id ? question : q)),
    });
    const visible = publicUnit(parsed).questions.find((q) => q.id === seed.id);
    // 公开载荷不能删去干扰词，也不能标出哪些词未进入正确答案。
    expect(visible).toHaveProperty("tokens", question.tokens);
    expect(visible).not.toHaveProperty("acceptedOrders");
    expect(visible).toHaveProperty("audio", { assetId: "test.competition" });
    expect(
      gradeAnswer(question, {
        kind: "arrange",
        tokenIds: ["i", "am", "name"],
      }).outcome,
    ).toBe("correct");
    // 语法成立但姓名与录音不同：应判内容错误，而非格式错误。
    expect(
      gradeAnswer(question, {
        kind: "arrange",
        tokenIds: ["i", "am", "other"],
      }).outcome,
    ).toBe("incorrect");
    expect(
      gradeAnswer(question, {
        kind: "arrange",
        tokenIds: ["i", "am", "name", "other"],
      }).outcome,
    ).toBe("incorrect");
  });
  it("验证六种题型，并拒绝答案不存在、标识重复及未覆盖的目标", () => {
    const unit = learningFixture();
    expect(unitSchema.safeParse(unit).success).toBe(true);
    expect(
      unitSchema.safeParse({
        ...unit,
        questions: [...unit.questions.slice(0, 5), unit.questions[0]],
      }).success,
    ).toBe(false);
    expect(
      unitSchema.safeParse({ ...unit, goalIds: [...unit.goalIds, "test.uncovered"] })
        .success,
    ).toBe(false);
    const first = unit.questions[0];
    expect(
      unitSchema.safeParse({
        ...unit,
        questions: [{ ...first, answer: "missing" }, ...unit.questions.slice(1)],
      }).success,
    ).toBe(false);
  });
  it("公共投影不泄露答案、解析、听写原文和内部审核信息", () => {
    const visible = publicUnit(learningFixture());
    for (const q of visible.questions) {
      for (const key of [
        "answer",
        "acceptedAnswers",
        "acceptedOrders",
        "answerPairs",
        "explanation",
        "difficultyReason",
      ]) {
        expect(q).not.toHaveProperty(key);
      }
    }
    expect(visible.questions[1]).toHaveProperty("audio", { assetId: "test.water" });
    expect(visible.questions[4]).toHaveProperty("audio", { assetId: "test.hello" });
    expect(visible).not.toHaveProperty("authorship");
  });
  it("内容指纹与对象字段顺序无关，答案变化一定改变指纹", () => {
    expect(contentHash({ a: 1, b: 2 })).toBe(contentHash({ b: 2, a: 1 }));
    expect(contentHash(learningFixture())).not.toBe(
      contentHash({ ...learningFixture(), version: 2 }),
    );
  });
});

describe("独立判题", () => {
  it("六种题型各自正确判分，跳过永远不算正确", () => {
    const answers = [
      { kind: "choice", optionId: "hello" },
      { kind: "choice", optionId: "water" },
      { kind: "arrange", tokenIds: ["i", "am", "name"] },
      { kind: "text", text: "I’m Oliver!" },
      { kind: "text", text: "Hello" },
      {
        kind: "matching",
        pairs: [
          { left: "bye", right: "farewell" },
          { left: "hello", right: "greeting" },
        ],
      },
    ];
    learningFixture().questions.forEach((question, i) => {
      expect(gradeAnswer(question, answerSchema.parse(answers[i])).outcome).toBe(
        "correct",
      );
      expect(gradeAnswer(question, { kind: "skip" }).outcome).toBe("skipped");
    });
  });
  it("不把错字、少词、错误配对和错误题型当作正确", () => {
    const unit = learningFixture();
    for (const question of unit.questions) {
      if (question.type === "dictation")
        expect(gradeAnswer(question, { kind: "text", text: "hello!" }).outcome).toBe(
          "incorrect",
        );
      if (question.type === "arrange") {
        expect(
          gradeAnswer(question, { kind: "arrange", tokenIds: ["i", "name"] }).outcome,
        ).toBe("incorrect");
        expect(() =>
          gradeAnswer(question, { kind: "arrange", tokenIds: ["i", "i"] }),
        ).toThrow();
      }
      if (question.type === "matching") {
        expect(
          gradeAnswer(question, {
            kind: "matching",
            pairs: [
              { left: "hello", right: "farewell" },
              { left: "bye", right: "greeting" },
            ],
          }).outcome,
        ).toBe("incorrect");
      }
      if (question.type === "choice")
        expect(() => gradeAnswer(question, { kind: "text", text: "hello" })).toThrow();
    }
  });
});

describe("字符与成长策略", () => {
  it.each([
    ["A B\n中", 3],
    ["e\u0301", 1],
    ["👨‍👩‍👧‍👦 🇨🇳", 2],
    ["\t \r\n", 0],
  ])("按字素计算 %s", (value, count) => {
    expect(countChatCharacters(value)).toBe(count);
  });
  it("星数封顶但保留原档超出点数", () => {
    expect(levelProgress(59).stars).toBe(0);
    expect(levelProgress(60).stars).toBe(1);
    expect(levelProgress(600)).toMatchObject({
      stars: 9,
      points: 600,
      displayPoints: 540,
    });
  });
  it("九星自动晋级不要求内容覆盖、迁移题或下一档题库", () => {
    const input = {
      level: "primary3" as const,
      points: 540,
      coveredGoalIds: ["introduce"],
      requiredGoalIds: ["introduce"],
      hasTransferUnit: true,
      nextLevelAvailable: true,
    };
    expect(promotionEligibility(input).ready).toBe(true);
    expect(promotionEligibility({ ...input, points: 539 }).ready).toBe(false);
    expect(promotionEligibility({ ...input, level: "advanced" }).ready).toBe(false);
    expect(promotionEligibility({ ...input, requiredGoalIds: [] }).ready).toBe(true);
    expect(promotionEligibility({ ...input, coveredGoalIds: [] }).ready).toBe(true);
    expect(promotionEligibility({ ...input, nextLevelAvailable: false }).ready).toBe(
      true,
    );
    expect(promotionEligibility({ ...input, hasTransferUnit: false }).ready).toBe(true);
  });
});
