import { describe, it, expect } from "vitest";
import {
  assembleBankQuestions,
  bankIdentity,
  bankUnit,
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
  it("十二年级规则都能组成六题，原文与素材保留且不含重复题", () => {
    const candidates = catalog.entries.map((e): BankCandidate => ({
      ...e.question,
      seen: false,
      mastered: false,
    }));
    expect(new Set(catalog.blueprints.map((b) => b.level)).size).toBe(12);
    for (const b of catalog.blueprints) {
      const selected = assembleBankQuestions(
        b,
        candidates,
        "character.someone",
        new Set(),
        () => 0,
      );
      expect(selected, b.id).toHaveLength(6);
      expect(new Set(required(selected).map((q) => q.id)).size).toBe(6);
      const unit = bankUnit(
        b,
        required(selected),
        "assembled.test",
        "character.someone",
        "测试同行者",
      );
      expect(unit.beats[1]?.speaker).toBe("测试同行者");
      expect(unit.questions.map((q) => q.goalId)).toEqual(b.slots.map((s) => s.goalId));
    }
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
