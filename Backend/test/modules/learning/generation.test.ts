import { z } from "zod";
import { randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";
import { generationFixture } from "../../helpers/learning-generation.js";
import {
  generatedDraftSchema,
  reviewSchemaForUnit,
  validateGeneratedUnit,
  validateIndependentReview,
} from "../../../src/modules/learning/generation-content.js";

describe("补库内容硬门槛", () => {
  it("供应商实际收到的 Schema 只允许四种已开放文字题型", () => {
    const schema = JSON.stringify(z.toJSONSchema(generatedDraftSchema));
    for (const type of ["choice", "arrange", "completion", "matching"])
      expect(schema).toContain(`"const":"${type}"`);
    for (const type of ["listeningChoice", "dictation", "audioArrange"])
      expect(schema).not.toContain(`"const":"${type}"`);
  });
  it("盲审合同逐题限定真实标识，配对文字与跳过不能伪装成答案", async () => {
    const { unit, report } = await generationFixture(randomUUID());
    const schema = reviewSchemaForUnit(unit);
    expect(schema.safeParse(report).success).toBe(true);
    const q = unit.questions.find((q) => q.type === "matching");
    const check = report.questions.find((c) => c.questionId === q?.id);
    if (!q || !check) throw new Error("缺少配对夹具。");
    check.solution = {
      kind: "matching",
      pairs: q.left.map((l, i) => ({
        left: l.text,
        right: q.right[i]?.text ?? "错误",
      })),
    };
    expect(schema.safeParse(report).success).toBe(false);
    check.solution = { kind: "skip" };
    expect(schema.safeParse(report).success).toBe(false);
    const encoded = JSON.stringify(z.toJSONSchema(schema));
    expect(encoded).not.toContain('"const":"skip"');
    expect(encoded).toContain(q.left[0]?.id);
  });
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
  it("配对按实际词句去重：同操作文案不同材料可用，改标识或顺序不能伪装新题", async () => {
    const { blueprint, unit } = await generationFixture(randomUUID());
    const current = unit.questions.find((q) => q.type === "matching");
    if (!current) throw new Error("缺少配对测试题。");
    const different = structuredClone(current);
    different.left.forEach((o, i) => {
      o.text = ["Hello!", "Goodbye!", "Thank you!"][i] ?? "Please.";
    });
    different.right.forEach((o, i) => {
      o.text = ["问候", "告别", "感谢"][i] ?? "请求";
    });
    expect(() =>
      validateGeneratedUnit(unit, blueprint, [
        {
          id: "existing",
          title: "其他标题",
          scene: "其他场景",
          questions: [different],
        },
      ]),
    ).not.toThrow();
    const copied = structuredClone(current);
    copied.prompt = "重新写过的操作文案，内容仍然一样。";
    copied.left.reverse();
    copied.right.reverse();
    copied.left.forEach((o, i) => {
      o.id = `other-left-${String(i)}`;
    });
    copied.right.forEach((o, i) => {
      o.id = `other-right-${String(i)}`;
    });
    expect(() =>
      validateGeneratedUnit(unit, blueprint, [
        { id: "existing", title: "其他标题", scene: "其他场景", questions: [copied] },
      ]),
    ).toThrow("重复");
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
