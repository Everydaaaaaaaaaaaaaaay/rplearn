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
import { expansionCatalogOrigin } from "../../../src/modules/learning/expansion-origin.js";

const original = JSON.parse(
  readFileSync("config/learning/originals/catalog.json", "utf8"),
) as { units: { unit: unknown }[] };
const originals = original.units.map((e) => unitSchema.parse(e.unit));
const catalog = seniorPracticeCatalog();
// The reviewed direction registry describes the frozen pre-2026-10-28 corpus.
// New authored tasks use the sources for format, not for copied paper directions.
const historical = catalog.practices.filter(
  (p) =>
    !p.unit.id.startsWith("expansion.20261028.") &&
    !expansionCatalogOrigin(p.unit)?.startsWith("expansion.20261028."),
);
const active = [
  ...originals.filter((u) => !u.level.startsWith("senior")),
  ...loadExpansionCatalog().units.filter((u) => !u.level.startsWith("senior")),
  ...historical.map((p) => p.unit),
];

describe("source-bound paper directions", () => {
  it("preserves new authored directions instead of borrowing the old format sample's wording", () => {
    for (const unit of loadExpansionCatalog("b128", false, "2026-10-28").units) {
      const before = contentHash(unit);
      const shown = publicUnit(unit).questions;
      for (const [index, question] of unit.questions.entries()) {
        expect(practiceDirections(question, question.material ?? "")).toBeUndefined();
        expect(shown[index]?.instruction).toBe(publicQuestion(question).instruction);
      }
      expect(contentHash(unit)).toBe(before);
    }
  });

  it("removes reviewed grammar headings, including the reported B section, without removing prose or bracketed words", () => {
    const headings = new Set<string>(
      JSON.parse(
        readFileSync("../Scripts/data/practice-grammar-headings.json", "utf8"),
      ) as string[],
    );
    const grammar = active.filter((u) => u.originalGroup?.family === "passage_form");
    expect(grammar).toHaveLength(171);
    for (const unit of grammar)
      for (const q of publicUnit(unit).questions) {
        expect(headings.has(q.material?.split("\n\n", 1)[0] ?? "")).toBe(false);
        expect(q.instruction).not.toMatch(/\bworld\b/iu);
      }
    const reported = grammar.find((u) =>
      u.questions[0]?.material?.startsWith(
        "B. Quoting a translation and reading a letter\n\n",
      ),
    );
    expect(reported).toBeDefined();
    if (!reported) throw new Error("Missing reported practice");
    const before = contentHash(reported);
    for (const [index, q] of publicUnit(reported).questions.entries()) {
      expect(q.material).toBe(
        reported.questions[index]?.material?.split("\n\n").slice(1).join("\n\n"),
      );
      expect(q.material).toContain("____1____ (write)");
      expect(q.instruction).toBe(
        "Fill each gap with ONE word or the correct form of the word in brackets.",
      );
    }
    expect(contentHash(reported)).toBe(before);
  });

  it("covers all 48 frozen historical task families without changing source or question content", () => {
    expect(active).toHaveLength(1418);
    expect(new Set(active.map((u) => u.originalGroup?.family)).size).toBe(48);
    let responses = 0;
    for (const source of [
      ...active,
      ...originals,
      ...catalog.historicalPractices
        .filter((p) => !p.unit.id.startsWith("expansion.20261028."))
        .map((p) => p.unit),
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
  }, 15000);

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
    for (const practice of historical)
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
