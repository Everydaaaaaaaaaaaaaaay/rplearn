import { describe, it, expect } from "vitest";
import {
  assembleBankQuestions,
  bankIdentity,
  bankUnit,
  bankBlueprintSchema,
  bankQuestionSchema,
  type BankCandidate,
} from "../../../src/modules/learning/bank-content.js";
import { loadBankCatalog } from "../../../src/modules/learning/bank-catalog.js";
import {
  freshLearningFixture as learningFixture,
  learningFixture as legacyFixture,
} from "../../helpers/learning.js";

function required<T>(value: T | undefined | null): T {
  if (value === undefined || value === null) throw new Error("测试夹具缺少必要内容。");
  return value;
}

const catalog = await loadBankCatalog(
  new URL("../../../config/learning", import.meta.url).pathname,
);
describe("公共题库内容与组卷", () => {
  function exclusionFixture() {
    const unit = learningFixture();
    const candidates: BankCandidate[] = unit.questions.map((question, index) => ({
      id: `test.exclusion.${String(index)}`,
      version: 1,
      level: unit.level,
      topic: "daily",
      roleKeys: [],
      question: { ...question, goalId: `test.goal.${String(index)}` },
      references: unit.references,
      reviewNotes: "用于验证人工登记的互斥关系，不生成或评审教学内容。",
      seen: false,
      mastered: false,
    }));
    const blueprint = bankBlueprintSchema.parse({
      id: "test.exclusion",
      title: "互斥组卷检查",
      level: unit.level,
      topic: "daily",
      prerequisiteGoalIds: [],
      slots: candidates.map(({ question }) => ({
        goalId: question.goalId,
        type: question.type,
      })),
    });
    return { candidates, blueprint };
  }

  it("旧蓝图听写槽改选同目标的理解题，旧听写不再进入新卷", () => {
    const { candidates, blueprint } = exclusionFixture();
    const index = candidates.findIndex(
      (q) => q.question.type === "listeningCompletion",
    );
    const candidate = required(candidates[index]);
    const legacy = required(
      legacyFixture().questions.find((q) => q.type === "dictation"),
    );
    const replacement: BankCandidate = {
      ...candidate,
      id: "test.replacement",
      question: {
        id: "test.replacement",
        goalId: candidate.question.goalId,
        type: "listeningChoice",
        prompt: "What does the speaker say?",
        instruction: "Listen and choose.",
        hint: "Listen to the greeting.",
        explanation: "The speaker says hello.",
        difficultyReason: "Engineering test.",
        audio: legacy.audio,
        options: [
          { id: "a", text: "Hello." },
          { id: "b", text: "Goodbye." },
        ],
        answer: "a",
      },
    };
    const slot = required(blueprint.slots[index]);
    slot.type = "dictation";
    const selected = required(
      assembleBankQuestions(
        blueprint,
        [
          ...candidates.filter((_, i) => i !== index),
          { ...candidate, question: { ...legacy, goalId: candidate.question.goalId } },
          replacement,
        ],
        "anyone",
        new Set(),
        () => 0,
      ),
    );
    expect(selected[index]?.id).toBe(replacement.id);
    expect(selected.some((q) => q.question.type === "dictation")).toBe(false);
  });

  it("前题暴露后题答案时回溯选择替代题，仍保留完整题数与槽位", () => {
    const { candidates, blueprint } = exclusionFixture();
    const first = required(candidates[0]);
    const last = required(candidates[5]);
    first.exclusionGroupIds = ["test.same-answer"];
    last.exclusionGroupIds = ["test.same-answer"];
    const alternative = { ...first, id: "test.alternative", exclusionGroupIds: [] };
    const selected = required(
      assembleBankQuestions(
        blueprint,
        [...candidates, alternative],
        "anyone",
        new Set(),
        () => 0,
      ),
    );
    expect(selected).toHaveLength(6);
    expect(selected[0]?.id).toBe(alternative.id);
    expect(selected[5]?.id).toBe(last.id);
    expect(selected.map((q) => q.question.goalId)).toEqual(
      blueprint.slots.map((slot) => slot.goalId),
    );
  });

  it("末槽只有一题时先处理约束，不为无解分支耗尽十八题搜索预算", () => {
    const { candidates: fixture, blueprint: base } = exclusionFixture();
    const seed = required(fixture[0]);
    // 仅构造搜索图的工程夹具，不生成教学内容：旧算法需先遍历2^16个无效组合。
    const candidates: BankCandidate[] = Array.from({ length: 18 }, (_, index) =>
      Array.from({ length: index === 17 ? 1 : 2 }, (_, variant) => ({
        ...seed,
        id: `test.branch.${String(index)}.${String(variant)}`,
        question: { ...seed.question, goalId: `test.branch.goal${String(index)}` },
        exclusionGroupIds:
          (index === 0 && variant === 0) || index === 17 ? ["test.end-conflict"] : [],
      })),
    ).flat();
    const blueprint = bankBlueprintSchema.parse({
      ...base,
      slots: Array.from({ length: 18 }, (_, index) => ({
        goalId: `test.branch.goal${String(index)}`,
        type: seed.question.type,
      })),
    });
    const selected = required(
      assembleBankQuestions(blueprint, candidates, "anyone", new Set(), () => 0),
    );
    expect(selected).toHaveLength(18);
    expect(selected[0]?.id).toBe("test.branch.0.1");
    expect(selected[17]?.id).toBe("test.branch.17.0");
    expect(new Set(selected.map((q) => q.id)).size).toBe(18);
    expect(selected.map((q) => q.question.goalId)).toEqual(
      blueprint.slots.map((slot) => slot.goalId),
    );
  });

  it("互斥关系不随题序失效，也不会用冲突题或少题强行交卷", () => {
    const { candidates, blueprint } = exclusionFixture();
    required(candidates[0]).exclusionGroupIds = ["test.answer", "test.other"];
    required(candidates[5]).exclusionGroupIds = ["test.answer"];
    for (const slots of [blueprint.slots, [...blueprint.slots].reverse()]) {
      expect(
        assembleBankQuestions(
          { ...blueprint, slots },
          candidates,
          "anyone",
          new Set(),
          () => 0,
        ),
      ).toBeNull();
    }
  });

  it("新题冲突时可用已到期复习题，不能借用未到期或受角色限制的题", () => {
    const { candidates, blueprint } = exclusionFixture();
    const first = required(candidates[0]);
    first.exclusionGroupIds = ["test.answer"];
    required(candidates[5]).exclusionGroupIds = ["test.answer"];
    const review = {
      ...first,
      id: "test.review",
      exclusionGroupIds: [],
      seen: true,
      mastered: true,
      reviewDue: true,
    };
    expect(
      assembleBankQuestions(
        blueprint,
        [...candidates, review],
        "anyone",
        new Set(),
        () => 0,
      )?.[0]?.id,
    ).toBe(review.id);
    expect(
      assembleBankQuestions(
        blueprint,
        [...candidates, { ...review, reviewDue: false }],
        "anyone",
        new Set(),
      ),
    ).toBeNull();
    expect(
      assembleBankQuestions(
        blueprint,
        [...candidates, { ...review, roleKeys: ["other"] }],
        "anyone",
        new Set(),
      ),
    ).toBeNull();
  });

  it("互斥审核信息保留在题库合同中且不改变题目奖励身份", () => {
    const original = required(catalog.entries[0]).question;
    const annotated = bankQuestionSchema.parse({
      ...original,
      exclusionGroupIds: ["review.answer-family"],
    });
    expect(annotated.exclusionGroupIds).toEqual(["review.answer-family"]);
    expect(bankIdentity(annotated.question)).toBe(bankIdentity(original.question));
    expect(
      bankQuestionSchema.safeParse({
        ...original,
        exclusionGroupIds: ["review.same", "review.same"],
      }).success,
    ).toBe(false);
  });

  it("十八题规则一次组成完整长卷，缺一题时不降级或重复填充", () => {
    const unit = learningFixture();
    // 只复制工程夹具验证长度与事务边界，不生成教学内容。
    const candidates: BankCandidate[] = Array.from({ length: 18 }, (_, index) => ({
      id: `test.bank${String(index)}`,
      version: 1,
      level: unit.level,
      topic: "daily",
      roleKeys: [],
      question: {
        ...required(unit.questions[index % 6]),
        id: `test.local${String(index)}`,
      },
      references: unit.references,
      reviewNotes: "仅供测试",
      seen: false,
      mastered: false,
    }));
    const blueprint = bankBlueprintSchema.parse({
      id: "test.long",
      title: "十八题工程检查",
      level: unit.level,
      topic: "daily",
      prerequisiteGoalIds: [],
      slots: candidates.map((q) => ({
        goalId: q.question.goalId,
        type: q.question.type,
      })),
    });
    const selected = required(
      assembleBankQuestions(blueprint, candidates, "anyone", new Set(), () => 0),
    );
    expect(new Set(selected.map((q) => q.id)).size).toBe(18);
    expect(
      bankUnit(blueprint, selected, "test.assembled", "anyone", "同行者").questions,
    ).toHaveLength(18);
    expect(
      assembleBankQuestions(blueprint, candidates.slice(1), "anyone", new Set()),
    ).toBeNull();
    expect(
      bankBlueprintSchema.safeParse({
        ...blueprint,
        slots: blueprint.slots.slice(0, 17),
      }).success,
    ).toBe(false);
  });
  it("听后排序的卡片相同但听取顺序不同，不会误合并身份", () => {
    const seed = required(learningFixture().questions[2]);
    if (seed.type !== "arrange") throw new Error("缺少排序夹具。");
    const question = {
      ...seed,
      type: "audioArrange" as const,
      audio: { assetId: "test.order", text: "One, two, three.", voice: "M5" },
    };
    expect(bankIdentity(question)).not.toBe(
      bankIdentity({
        ...question,
        audio: { ...question.audio, text: "Three, two, one." },
      }),
    );
    expect(bankIdentity(question)).toBe(
      bankIdentity({ ...question, tokens: [...question.tokens].reverse() }),
    );
  });
  it("各档按已审题量组卷，完整故事保持前置且不含重复题", () => {
    const candidates = catalog.entries.map((e): BankCandidate => ({
      ...e.question,
      seen: false,
      mastered: false,
    }));
    expect(new Set(catalog.blueprints.map((b) => b.level)).size).toBe(15);
    for (const b of catalog.blueprints) {
      const selected = assembleBankQuestions(
        b,
        candidates,
        "character.someone",
        new Set(),
        () => 0,
      );
      expect(selected, b.id).toHaveLength(b.slots.length);
      expect(new Set(required(selected).map((q) => q.id)).size).toBe(b.slots.length);
      const unit = bankUnit(
        b,
        required(selected),
        "assembled.test",
        "character.someone",
        "测试同行者",
      );
      if (b.openingStory) {
        expect(unit.beats).toEqual(b.openingStory.beats);
        expect(unit.beats.every((beat) => beat.afterQuestion === 0)).toBe(true);
        expect(unit.summary).toBe(b.openingStory.title);
        expect(unit.estimatedMinutes).toBe(b.estimatedMinutes);
      } else {
        expect(unit.beats[1]?.speaker).toBe("测试同行者");
      }
      expect(unit.questions.map((q) => q.goalId)).toEqual(b.slots.map((s) => s.goalId));
    }
  });
  it("完整故事不能偷偷插入答题中，换角色不改故事和独立题目", () => {
    const b = required(catalog.blueprints.find((b) => b.level === "undergraduate"));
    const story = required(b.openingStory);
    expect(story.beats).toHaveLength(3);
    expect(b.slots).toHaveLength(18);
    expect(
      bankBlueprintSchema.safeParse({
        ...b,
        openingStory: {
          ...story,
          beats: story.beats.map((beat) => ({ ...beat, afterQuestion: 1 })),
        },
      }).success,
    ).toBe(false);
  });
  it("换角色或局部编号不会改变题目身份，解释修正不会重发奖励", () => {
    const q = required(learningFixture().questions[0]);
    if (q.type === "choice") {
      expect(bankIdentity(q)).toBe(
        bankIdentity({ ...q, answer: "bye", options: [...q.options].reverse() }),
      );
    }
    expect(bankIdentity(q)).toBe(
      bankIdentity({ ...q, id: "another", hint: "新提示", explanation: "新解析" }),
    );
  });
  it("不使用已见题、不跨级、不借用限定角色题，也不绕过先修条件", () => {
    const b = required(catalog.blueprints[0]);
    const entries = catalog.entries
      .filter((e) => e.unitId === b.id.slice(5))
      .map((e): BankCandidate => ({ ...e.question, seen: false, mastered: false }));
    expect(
      assembleBankQuestions(
        b,
        entries.map((q) => ({ ...q, seen: true })),
        "other",
        new Set(),
      ),
    ).toBeNull();
    expect(
      assembleBankQuestions(
        b,
        entries.map((q) => ({ ...q, level: "senior3" })),
        "other",
        new Set(),
      ),
    ).toBeNull();
    expect(
      assembleBankQuestions(
        b,
        entries.map((q) => ({ ...q, roleKeys: ["oliver"] })),
        "other",
        new Set(),
      ),
    ).toBeNull();
    expect(
      assembleBankQuestions(
        { ...b, prerequisiteGoalIds: ["required"] },
        entries,
        "other",
        new Set(),
      ),
    ).toBeNull();
  });
});
