import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { generationFixture } from "../../helpers/learning-generation.js";
import {
  validateGeneratedUnit,
  validateIndependentReview,
} from "../../../src/modules/learning/generation-content.js";

describe("补库内容硬门槛", () => {
  it("合同通过仍需独立解题；拒绝错误答案、skip 反例和缺失题目", async () => {
    const { blueprint, unit, report } = await generationFixture(randomUUID());
    expect(validateGeneratedUnit(unit, blueprint, []).questions).toHaveLength(6);
    expect(
      validateIndependentReview(JSON.stringify(report), unit).questions,
    ).toHaveLength(6);
    const bad = structuredClone(report);
    const first = bad.questions[0];
    if (!first) throw new Error("缺少测试审题。");
    first.solution = first.incorrectExample;
    expect(() => validateIndependentReview(JSON.stringify(bad), unit)).toThrow();
    const skipped = {
      ...report,
      questions: report.questions.map((q) => ({
        ...q,
        incorrectExample: { kind: "skip" },
      })),
    };
    expect(() => validateIndependentReview(JSON.stringify(bad), unit)).toThrow();
    expect(() => validateIndependentReview(JSON.stringify(skipped), unit)).toThrow();
    report.questions.pop();
    expect(() => validateIndependentReview(JSON.stringify(report), unit)).toThrow();
  });
  it("禁止换档、未审媒体、剧情依赖及改名字伪新题", async () => {
    const { blueprint, unit } = await generationFixture(randomUUID());
    expect(() =>
      validateGeneratedUnit({ ...unit, level: "senior2" }, blueprint, []),
    ).toThrow();
    expect(() =>
      validateGeneratedUnit(unit, blueprint, [
        { ...unit, id: "other", title: "改名无效" },
      ]),
    ).toThrow();
    const noImage = structuredClone(unit);
    const hinted = noImage.questions[0];
    if (!hinted) throw new Error("缺少测试题目。");
    hinted.hint = "先看图旁的英文，再选择合适答案。";
    expect(() => validateGeneratedUnit(noImage, blueprint, [])).toThrow();
    const changed = structuredClone(unit);
    const firstQuestion = changed.questions[0];
    if (!firstQuestion) throw new Error("缺少测试题目。");
    firstQuestion.prompt = "根据故事中她的介绍作答。";
    expect(() => validateGeneratedUnit(changed, blueprint, [])).toThrow();
    const q = changed.questions.find((q) => q.type === "choice");
    const option = q?.options[0];
    if (!option) throw new Error("测试缺少选择项。");
    firstQuestion.prompt = unit.questions[0]?.prompt ?? "";
    option.imageAssetId = "fake.image";
    expect(() => validateGeneratedUnit(changed, blueprint, [])).toThrow();
  });
});
