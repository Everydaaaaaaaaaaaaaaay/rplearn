import { describe, it, expect } from "vitest";
import { loadGaokaoCatalog } from "../../../src/modules/learning/gaokao-catalog.js";
import {
  gaokaoCatalog,
  isAdmittedGaokaoUnit,
} from "../../../src/modules/learning/gaokao-policy.js";
import { contentHash, publicUnit } from "../../../src/modules/learning/content.js";
import { availableForNewLearning } from "../../../src/modules/learning/bank-content.js";
import { isExpansionUnit } from "../../../src/modules/learning/expansion-catalog.js";

function required<T>(v: T | undefined): T {
  if (v === undefined) throw new Error("Missing fixture");
  return v;
}

describe("高中高考真题完整组准入", () => {
  it("高一至高三仅绑定可追溯真题；每档四次练习、45个独立原题", async () => {
    const c = await loadGaokaoCatalog();
    expect(c.units.filter((u) => !isExpansionUnit(u))).toHaveLength(60);
    const paperIds = new Set(
      gaokaoCatalog()
        .practices.filter((p) => p.kind === "past-paper")
        .map((p) => p.unit.id),
    );
    for (const level of ["senior1", "senior2", "senior3"]) {
      const units = c.units.filter((u) => u.level === level && paperIds.has(u.id));
      expect(units.map((u) => u.questions.length)).toEqual([7, 8, 15, 15]);
      expect(new Set(units.flatMap((u) => u.questions.map((q) => q.id))).size).toBe(45);
      expect(
        units.every(
          (u) =>
            u.estimatedMinutes >= 14 &&
            u.estimatedMinutes <= 18 &&
            u.beats.length === 0,
        ),
      ).toBe(true);
      expect(units.every(isAdmittedGaokaoUnit)).toBe(true);
    }
  });
  it("原创须明确标注并按完整高考题型组合；不恢复十空完形和独立配对", () => {
    const authored = gaokaoCatalog().practices.filter((p) => p.kind === "authored");
    const oldAuthored = authored.filter((p) => !isExpansionUnit(p.unit));
    expect(oldAuthored).toHaveLength(48);
    expect(
      new Set(oldAuthored.flatMap((p) => p.unit.questions.map((q) => q.id))).size,
    ).toBe(477);
    expect(
      authored.every(
        (p) =>
          p.unit.title.startsWith("高考题型原创") &&
          p.unit.originalGroup?.sourceNotice.includes("非高考真题"),
      ),
    ).toBe(true);
    expect(
      authored.every((p) =>
        p.components.every((c) => Boolean(c.sourceUnitId && c.sourceContentHash)),
      ),
    ).toBe(true);
    expect(
      authored.every((p) =>
        p.unit.questions.every((q) => q.type === "choice" || q.type === "completion"),
      ),
    ).toBe(true);
    expect(
      authored
        .filter((p) => p.components[0]?.family === "choice_cloze")
        .every((p) => p.unit.questions.length === 15),
    ).toBe(true);
    const reading = authored.find((p) =>
      p.components.every((c) => c.family === "reading_choice"),
    );
    const p = required(reading);
    const first = required(p.unit.questions[0]);
    const second = required(p.unit.questions[p.components[0]?.questionIds.length ?? 0]);
    expect(first.material).not.toEqual(second.material);
    expect(first.prompt).not.toMatch(/^[A-Z]组/);
  });
  it("篡改正文、答案、选项、年级或只贴真题标签不能取得准入", () => {
    const u = required(gaokaoCatalog().practices[0]).unit;
    const q = required(u.questions[0]);
    expect(isAdmittedGaokaoUnit({ ...u, title: "模拟题" })).toBe(false);
    expect(isAdmittedGaokaoUnit({ ...u, level: "senior3" })).toBe(false);
    expect(
      isAdmittedGaokaoUnit({
        ...u,
        questions: [{ ...q, material: "changed" }, ...u.questions.slice(1)],
      }),
    ).toBe(false);
    expect(availableForNewLearning(q, "senior3")).toBe(false);
  });
  it("两篇阅读保留各篇全文与必要原图，换题不混正文且不泄漏答案", () => {
    const u = required(gaokaoCatalog().practices[0]).unit;
    const frozenHash = contentHash(u);
    const view = publicUnit(u);
    expect(required(view.questions[0]).material).toContain(
      "different modes of transport.",
    );
    expect(required(view.questions[3]).material).toContain(
      "In my ninth-grade writing class",
    );
    expect(required(view.questions[3]).material).not.toContain(
      "The greening of planes",
    );
    expect(required(view.questions[0]).materialImages).toHaveLength(1);
    expect(required(view.questions[3]).materialImages ?? []).toHaveLength(0);
    expect(JSON.stringify(view)).not.toContain("acceptedAnswers");
    expect(JSON.stringify(view)).not.toMatch(/"answer":/);
    expect(contentHash(u)).toBe(frozenHash);
  });
  it("完形十五空、七选五五空和语法十空保留完整数字化空位", () => {
    const practices = gaokaoCatalog().practices.filter((p) => p.kind === "past-paper");
    for (const p of practices)
      for (const c of p.components) {
        expect(c.questionIds).toHaveLength(c.sourceNumbers.length);
        const material = required(
          required(p.unit.questions.find((q) => q.id === c.questionIds[0])).material,
        );
        if (c.family !== "reading_choice")
          for (const n of c.sourceNumbers)
            expect(material).toContain(`____${String(n)}____`);
      }
  });
});
