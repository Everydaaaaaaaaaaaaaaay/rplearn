import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  contentHash,
  publicQuestion,
  publicUnit,
  unitSchema,
} from "../../../src/modules/learning/content.js";
import { loadExpansionCatalog } from "../../../src/modules/learning/expansion-catalog.js";
import { seniorPracticeCatalog } from "../../../src/modules/learning/senior-practice-catalog.js";
import { practiceDirections } from "../../../src/modules/learning/practice-directions.js";

const original = JSON.parse(
  readFileSync("config/learning/originals/catalog.json", "utf8"),
) as { units: { unit: unknown }[] };
const originals = original.units.map((e) => unitSchema.parse(e.unit));
const catalog = seniorPracticeCatalog();
const active = [
  ...originals.filter((u) => !u.level.startsWith("senior")),
  ...loadExpansionCatalog().units.filter((u) => !u.level.startsWith("senior")),
  ...catalog.practices.map((p) => p.unit),
];

describe("source-bound paper directions", () => {
  it("covers all 48 current task families and frozen historical groups without changing source or question content", () => {
    expect(active).toHaveLength(1418);
    expect(new Set(active.map((u) => u.originalGroup?.family)).size).toBe(48);
    let responses = 0;
    for (const source of [
      ...active,
      ...originals,
      ...catalog.historicalPractices.map((p) => p.unit),
    ]) {
      const before = contentHash(source);
      const shown = publicUnit(source);
      for (const [index, q] of source.questions.entries()) {
        const material = q.material ?? source.originalGroup?.material ?? "";
        const patch = practiceDirections(q, material);
        expect(patch, `${source.id}/${q.id}`).toBeDefined();
        const displayed = shown.questions[index];
        expect(displayed?.instruction).not.toMatch(/\p{Script=Han}/u);
        expect(displayed?.instruction.length).toBeLessThanOrEqual(240);
        // Existing reviewed prompt/option translations must still apply.
        expect(displayed).toEqual({
          ...publicQuestion(q),
          instruction: patch?.instruction,
          material: patch?.material,
        });
        expect(displayed).not.toHaveProperty("answer");
        expect(displayed).not.toHaveProperty("acceptedAnswers");
        expect(displayed).not.toHaveProperty("marking");
        expect(material.trimEnd().endsWith(patch?.material.trimEnd() ?? "")).toBe(true);
        responses++;
      }
      expect(contentHash(source)).toBe(before);
    }
    expect(responses).toBeGreaterThan(11871);
  });

  it("removes both single-choice administrative blocks, including group material fallback", () => {
    const singles = catalog.practices.filter(
      (p) => p.unit.originalGroup?.family === "sentence_choice",
    );
    for (const { unit } of singles)
      for (const q of publicUnit(unit).questions) {
        expect(q.instruction).toBe("Choose the best answer.");
        expect(q.material).toBe("");
      }
    const raw = originals.find((u) => u.id === singles[0]?.components[0]?.sourceUnitId);
    expect(raw).toBeDefined();
    expect(raw && publicUnit(raw).questions[0]?.material).toBe("");
  });

  it("preserves printed glosses, the whole passage, word limits, form rules and explicit reuse rules", () => {
    const past = active.find((u) => u.id === "gaokao.senior3.2025-national1.cloze");
    expect(past).toBeDefined();
    expect(past && publicUnit(past).questions[0]?.material).toBe(
      past?.questions[0]?.material,
    );
    expect(past && publicUnit(past).questions[0]?.material).toContain("垃圾填埋场");
    const grammar = active.filter((u) => u.originalGroup?.family === "passage_form");
    for (const u of grammar)
      for (const q of publicUnit(u).questions)
        expect(q.instruction).not.toContain("choose");
    const special = originals.find((u) =>
      u.questions[0]?.instruction.includes("第10空已明确标注"),
    );
    expect(special && publicUnit(special).questions[0]?.instruction).toContain(
      "TWO words in gap 10",
    );
    const once = originals.find(
      (u) =>
        u.originalGroup?.family === "shared_insertion" &&
        u.originalGroup.material.includes("每个选项最多使用一次"),
    );
    expect(once && publicUnit(once).questions[0]?.instruction).toContain(
      "at most once",
    );
    const noOnce = originals.find(
      (u) =>
        u.originalGroup?.family === "dialogue_matching" &&
        u.questions[0]?.instruction.includes("原参照未明示每项只用一次"),
    );
    expect(noOnce && publicUnit(noOnce).questions[0]?.instruction).not.toContain(
      "once",
    );
    const bank = originals.find(
      (u) =>
        u.originalGroup?.family === "shared_bank" &&
        u.questions[0]?.instruction.includes("每空仅填1词"),
    );
    expect(bank && publicUnit(bank).questions[0]?.instruction).toContain(
      "correct form",
    );
    expect(bank && publicUnit(bank).questions[0]?.instruction).toContain("ONE word");
  });

  it("does not apply a reviewed rule to changed answers, marking or prose with reused IDs", () => {
    const q = catalog.practices.find(
      (p) => p.unit.originalGroup?.family === "sentence_choice",
    )?.unit.questions[0];
    if (q?.type !== "choice") throw new Error("Missing choice fixture");
    const material = q.material ?? "";
    expect(
      practiceDirections({ ...q, id: "question.composed" }, material),
    ).toBeDefined();
    expect(
      practiceDirections({ ...q, answer: "a-new-answer" }, material),
    ).toBeUndefined();
    expect(practiceDirections(q, material + "\nA new passage.")).toBeUndefined();
    expect(
      practiceDirections({ ...q, instruction: "New task rules." }, material),
    ).toBeUndefined();
  });

  it("retains source component constraints after splitting and preserves the printed option spacing", () => {
    const byId = new Map(originals.map((u) => [u.id, u]));
    for (const practice of catalog.practices)
      for (const component of practice.components) {
        const source = component.sourceUnitId && byId.get(component.sourceUnitId);
        if (source) {
          const originalDirections = publicUnit(source).questions;
          const shown = publicUnit(practice.unit).questions;
          for (const [index, id] of component.questionIds.entries()) {
            const number = component.sourceNumbers[index];
            expect(shown.find((q) => q.id === id)?.instruction).toBe(
              originalDirections[(number ?? 1) - 1]?.instruction,
            );
          }
        }
        if (practice.kind === "past-paper" && component.family === "shared_insertion") {
          for (const q of publicUnit(practice.unit).questions) {
            expect(q.instruction).toContain("two extra options");
            expect("options" in q && q.options[0]?.text).toBe(
              "The cafe closes at 9 pm every day.",
            );
          }
        }
      }
  });
});
