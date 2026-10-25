import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  contentHash,
  publicUnit,
  unitSchema,
} from "../../../src/modules/learning/content.js";
import { gaokaoCatalog } from "../../../src/modules/learning/gaokao-policy.js";
import { gradeAnswer } from "../../../src/modules/learning/grading.js";
import {
  isAdmittedSeniorUnit,
  seniorPracticeCatalog,
  seniorPracticeIds,
  selectSeniorCandidate,
} from "../../../src/modules/learning/senior-practice-catalog.js";
import { z } from "zod";

describe("高中独立客观专项", () => {
  it("每档独立提供五类；七选五五题、语法十题、单选十五或二十题", () => {
    const catalog = seniorPracticeCatalog();
    for (const level of ["senior1", "senior2", "senior3"]) {
      const practices = catalog.practices.filter((p) => p.unit.level === level);
      expect(new Set(practices.map((p) => p.unit.originalGroup?.family))).toEqual(
        new Set([
          "reading_choice",
          "choice_cloze",
          "shared_insertion",
          "passage_form",
          "sentence_choice",
        ]),
      );
      for (const p of practices) {
        expect(p.components.every((c) => c.family === p.components[0]?.family)).toBe(
          true,
        );
        if (p.unit.originalGroup?.family === "shared_insertion")
          expect(p.unit.questions).toHaveLength(5);
        if (p.unit.originalGroup?.family === "passage_form")
          expect(p.unit.questions).toHaveLength(10);
        if (p.unit.originalGroup?.family === "sentence_choice")
          expect([15, 20]).toContain(p.unit.questions.length);
        expect(isAdmittedSeniorUnit(p.unit)).toBe(true);
      }
    }
    const singles = catalog.practices.filter(
      (p) => p.unit.originalGroup?.family === "sentence_choice",
    );
    expect(singles).toHaveLength(9);
    expect(singles.reduce((n, p) => n + p.unit.questions.length, 0)).toBe(150);
  });
  it("组合只退出新抽取；旧题载荷、所有作答身份、参考键和完整材料保持不变", () => {
    const before = gaokaoCatalog().practices.map((p) => contentHash(p.unit));
    const catalog = seniorPracticeCatalog();
    expect(catalog.historicalPractices.map((p) => contentHash(p.unit))).toEqual(before);
    for (const old of catalog.historicalPractices) {
      expect(isAdmittedSeniorUnit(old.unit)).toBe(true);
      if (
        old.components.length === 1 ||
        old.components.every((c) => c.family === "reading_choice")
      )
        continue;
      expect(seniorPracticeIds()).not.toContain(old.unit.id);
      for (const c of old.components) {
        const derived = catalog.practices.find(
          (p) =>
            p.unit.level === old.unit.level &&
            p.components.length === 1 &&
            p.components[0]?.id === c.id,
        );
        expect(derived).toBeDefined();
        expect(derived?.unit.questions).toEqual(
          old.unit.questions.filter((q) => c.questionIds.includes(q.id)),
        );
      }
    }
  });
  it("单选复用已审核整组，逐题候选、答案及材料与原稿一致，不改成主观或听力", () => {
    const original = z
      .object({ units: z.array(z.object({ unit: unitSchema })) })
      .parse(
        JSON.parse(
          readFileSync(
            new URL("../../../config/learning/originals/catalog.json", import.meta.url),
            "utf8",
          ),
        ) as unknown,
      );
    for (const p of seniorPracticeCatalog().practices) {
      expect(
        p.unit.questions.every(
          (q) => q.type === "choice" || (q.type === "completion" && !!q.marking),
        ),
      ).toBe(true);
      if (p.unit.originalGroup?.family !== "sentence_choice") continue;
      const source = original.units.find(
        (e) => e.unit.id === p.components[0]?.sourceUnitId,
      )?.unit;
      expect(source).toBeDefined();
      expect(source && contentHash(source)).toBe(p.components[0]?.sourceContentHash);
      for (const [index, q] of p.unit.questions.entries()) {
        expect(q).toEqual({
          ...source?.questions[index],
          id: q.id,
          material: source?.originalGroup?.material,
        });
      }
      for (const q of p.unit.questions) {
        expect(gradeAnswer(q, gradeAnswer(q, { kind: "skip" }).solution).outcome).toBe(
          "correct",
        );
      }
      expect(JSON.stringify(publicUnit(p.unit))).not.toContain('"answer":');
    }
  });
  it("抽取按五类而非组数分配；有其他类时避开上次", () => {
    const candidates = seniorPracticeCatalog()
      .practices.filter((p) => p.unit.level === "senior3")
      .map((p) => ({ payload: p.unit }));
    const previous = candidates.find(
      (c) => c.payload.originalGroup?.family === "choice_cloze",
    );
    expect(previous).toBeDefined();
    const families = new Set<string>();
    for (const r of [0, 0.26, 0.51, 0.99]) {
      const chosen = selectSeniorCandidate(candidates, previous?.payload.id, () => r);
      expect(chosen?.payload.originalGroup?.family).not.toBe("choice_cloze");
      families.add(chosen?.payload.originalGroup?.family ?? "");
    }
    expect(families.size).toBe(4);
  });
});
