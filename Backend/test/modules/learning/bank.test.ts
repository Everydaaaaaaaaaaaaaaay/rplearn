import { describe, it, expect } from "vitest";
import {
  assembleBankQuestions,
  bankIdentity,
  bankUnit,
  bankBlueprintSchema,
  type BankCandidate,
} from "../../../src/modules/learning/bank-content.js";
import { loadBankCatalog } from "../../../src/modules/learning/bank-catalog.js";
import { learningFixture } from "../../helpers/learning.js";

function required<T>(value: T | undefined | null): T {
  if (value === undefined || value === null) throw new Error("测试夹具缺少必要内容。");
  return value;
}

const catalog = await loadBankCatalog(
  new URL("../../../config/learning", import.meta.url).pathname,
);
describe("公共题库内容与组卷", () => {
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
    expect(new Set(catalog.blueprints.map((b) => b.level)).size).toBe(13);
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
