import { describe, expect, it } from "vitest";
import { readFileSync } from "node:fs";
import { authoredUnitSeeds } from "../../../src/modules/learning/unit-seeds.js";
import { validateGeneratedUnit } from "../../../src/modules/learning/unit-generator.js";

function tokens(text: string): string[] {
  return (text.match(/[\p{L}\p{N}']+|[.!?]/gu) ?? []).map(value => value.toLowerCase()).sort();
}

describe("authored unit library", () => {
  it("covers every school year twice for each main character with six checkable questions", () => {
    expect(authoredUnitSeeds).toHaveLength(72);
    expect(new Set(authoredUnitSeeds.map(unit => unit.id)).size).toBe(72);
    expect(authoredUnitSeeds.every(unit => unit.id.startsWith("unit-v3-"))).toBe(true);
    for (const role of ["oliver", "ruby", "marcus"])
      for (let grade = 1; grade <= 12; grade += 1) {
        const units = authoredUnitSeeds.filter(unit => unit.roleKey === role && unit.grade === grade);
        expect(units).toHaveLength(2);
        expect(new Set(units.map(unit => unit.scene.map(beat => beat.english).join("\n"))).size).toBe(2);
        for (const unit of units) {
          expect(() => validateGeneratedUnit(unit, role, grade)).not.toThrow();
          expect(unit.scene.some(beat => beat.speaker === "character")).toBe(true);
          expect(unit.scene.every(beat => !beat.english.includes("{") && !beat.chinese.includes("{"))).toBe(true);
          if (grade <= 2) expect(unit.scene.every(beat => beat.english.split(/\s+/u).length <= 16)).toBe(true);
          expect(unit.questions).toHaveLength(6);
          expect(new Set(unit.questions.map(question => question.kind))).toEqual(new Set(["choice", "order", "write", "multi"]));
          for (const question of unit.questions) {
            if (question.kind === "write") {
              const count = /(?:填|写|填写|写出)([一二三四五六两])词/u.exec(question.prompt)?.[1];
              if (count) {
                const expected = ({ 一: 1, 二: 2, 两: 2, 三: 3, 四: 4, 五: 5, 六: 6 } as Record<string, number>)[count];
                expect(question.answer.trim().split(/\s+/u).length, `${unit.id} 题干词数与答案不符`).toBe(expected);
              }
            }
            if (question.kind === "choice") {
              expect(question.options).toHaveLength(3);
              expect(question.options.filter(option => option === question.answer)).toHaveLength(1);
            } else if (question.kind === "multi") {
              expect(question.options).toHaveLength(4);
              expect(question.answer.split("|")).toHaveLength(2);
              expect(question.answer.split("|").every(answer => question.options.includes(answer))).toBe(true);
            } else if (question.kind === "order") {
              expect(tokens(question.options.join(" "))).toEqual(tokens(question.answer));
              expect(question.options.join(" ")).not.toBe(question.answer);
            } else {
              expect(question.options).toHaveLength(0);
              expect(question.answer.length).toBeGreaterThan(1);
              if (grade >= 10) expect(question.answer.trim().split(/\s+/u).length).toBeGreaterThanOrEqual(4);
            }
          }
        }
      }
  });

  it("keeps role scenes distinct and records the actual evidence depth of each textbook reference", () => {
    const catalog = JSON.parse(readFileSync(new URL("../../../../docs/learning-program/textbooks/pep/catalog.json", import.meta.url), "utf8")) as {
      volumes: { id: string; units: { number: number }[] }[];
    };
    const volumes = new Map(catalog.volumes.map(volume => [volume.id, volume]));
    for (let grade = 1; grade <= 12; grade += 1) {
      const units = authoredUnitSeeds.filter(unit => unit.grade === grade);
      expect(new Set(units.map(unit => unit.roleKey))).toEqual(new Set(["oliver", "ruby", "marcus"]));
      expect(new Set(units.map(unit => unit.scene.map(beat => beat.english).join("\n"))).size).toBe(6);
    }
    for (const unit of authoredUnitSeeds) {
      expect(unit.scene.length).toBeGreaterThanOrEqual(3);
      expect(unit.learningReference?.evidenceUrl).toMatch(/^https:\/\/(www\.)?(pep\.com\.cn|moe\.gov\.cn)\//);
      if (unit.grade <= 2) {
        expect(unit.learningReference?.evidenceLevel).toBe("curriculum-introduction");
        expect(unit.learningReference?.volumeId).toBe("pep-preparatory-unverified");
        continue;
      }
      expect(["sample-page", "publisher-activity-index", "official-lesson-index"]).toContain(unit.learningReference?.evidenceLevel);
      const volume = volumes.get(unit.learningReference?.volumeId ?? "");
      expect(volume?.units.some(item => item.number === unit.learningReference?.unitNumber)).toBe(true);
      expect(unit.questions[0]?.explanation.length).toBeGreaterThanOrEqual(8);
    }
  });

  it("rejects generated choices and multi-select with invalid answers", () => {
    const valid = authoredUnitSeeds[0];
    if (!valid) throw Error("缺少原创题库样本");
    expect(() => validateGeneratedUnit(valid, "oliver", 1)).not.toThrow();
    const first = valid.questions[0];
    const multi = valid.questions[2];
    if (!first || !multi) throw Error("缺少题目样本");
    const ambiguous = { ...valid, questions: [{ ...first, options: [first.answer, first.answer, "其他"] }, ...valid.questions.slice(1)] };
    expect(() => validateGeneratedUnit(ambiguous, "oliver", 1)).toThrow();
    const invalidMulti = { ...valid, questions: valid.questions.map(question => question.id === multi.id
      ? { ...question, answer: "不存在|也不存在" } : question) };
    expect(() => validateGeneratedUnit(invalidMulti, "oliver", 1)).toThrow();
    const alreadyOrdered = { ...valid, questions: valid.questions.map(question => question.kind === "order"
      ? { ...question, options: question.answer.match(/[\p{L}\p{N}']+|[.!?]/gu) ?? [] } : question) };
    expect(() => validateGeneratedUnit(alreadyOrdered, "oliver", 1)).toThrow();
  });

  it("requires generated secondary-school writing to synthesize rather than copy the scene", () => {
    const senior = authoredUnitSeeds.find(unit => unit.id === "unit-v3-marcus-g10-1");
    if (!senior) throw Error("缺少高中题目样本");
    expect(() => validateGeneratedUnit(senior, "marcus", 10)).not.toThrow();
    const copied = { ...senior, questions: senior.questions.map(question => question.kind === "write"
      ? { ...question, answer: "A child is visible in the foreground" } : question) };
    expect(() => validateGeneratedUnit(copied, "ruby", 12)).toThrow();
    const short = {
      ...senior,
      questions: senior.questions.map(question => question.kind === "write"
        ? { ...question, answer: "by Monday" } : question),
    };
    expect(() => validateGeneratedUnit(short, "marcus", 10)).toThrow();
  });
});
