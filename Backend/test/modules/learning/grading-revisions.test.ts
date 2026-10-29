import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  contentHash,
  publicQuestion,
  unitSchema,
  type LearningQuestion,
} from "../../../src/modules/learning/content.js";
import { gradeAnswer } from "../../../src/modules/learning/grading.js";
import { loadExpansionCatalog } from "../../../src/modules/learning/expansion-catalog.js";

const raw = JSON.parse(
  readFileSync(
    new URL(
      "../../../config/learning/expansions/2026-10-28/b005.json",
      import.meta.url,
    ),
    "utf8",
  ),
) as { entries: { unit: unknown }[] };
const unit = raw.entries
  .map((e) => unitSchema.parse(e.unit))
  .find((u) => u.id === "expansion.20261028.primary6.courtesy-grammar-workshop-005");
const source = unit?.questions.find((q) => q.id.endsWith(".q4"));
if (source?.type !== "completion" || !source.marking)
  throw new Error("Missing frozen slow fixture");
const question = source;
const sourceMarking = source.marking;
const text = (value: string) => ({ kind: "text" as const, text: value });
function bounded(min: number | undefined, max: number | null): LearningQuestion {
  const marking = { ...sourceMarking, maxWords: max, rejectedAnswers: [] };
  if (min !== undefined) marking.minWords = min;
  else Reflect.deleteProperty(marking, "minWords");
  return {
    ...question,
    id: "test.bound",
    instruction: "Complete the sentence.",
    prompt: "Gap 1.",
    material: "A fully stated engineering fixture sentence.",
    marking,
  };
}

describe("reviewed frozen answer correction", () => {
  it("accepts exactly reviewed slow/slowly forms while preserving old payload and canonical solution", () => {
    const snapshot = structuredClone(question),
      before = contentHash(question);
    expect(gradeAnswer(question, text("slow")).outcome).toBe("correct");
    expect(gradeAnswer(question, text("slowly")).outcome).toBe("correct");
    for (const variant of ["slower", "slowest"])
      expect(gradeAnswer(question, text(variant)).outcome).toBe("incorrect");
    for (const invalid of ["slowlyer", "slowliest"])
      expect(gradeAnswer(question, text(invalid)).outcome).toBe("incorrect");
    expect(gradeAnswer(question, text("slow")).solution).toEqual(text("slowly"));
    expect(gradeAnswer(question, text("slow")).explanation).toContain("平义副词slow");
    publicQuestion(question);
    expect(question).toEqual(snapshot);
    expect(contentHash(question)).toBe(before);
    expect(question.acceptedAnswers).toEqual(["slowly"]);
    expect(question.marking?.rejectedAnswers).toContain("slow");
  });

  it("survives remapped question IDs but cannot reach a similar question with different content", () => {
    expect(
      gradeAnswer({ ...question, id: "question.remapped-bank-id" }, text("slow"))
        .outcome,
    ).toBe("correct");
    expect(
      gradeAnswer(
        { ...question, prompt: question.prompt + " Use the form ending in -ly." },
        text("slow"),
      ).outcome,
    ).toBe("incorrect");
  });

  it("validates the unchanged old batch using explicitly reviewed effective probes", () => {
    const catalog = loadExpansionCatalog("b005", false, "2026-10-28");
    expect(catalog.hash).toBe(contentHash([raw]));
    const frozen = catalog.units
      .find((u) => u.id === unit?.id)
      ?.questions.find((q) => q.id === question.id);
    expect(frozen).toEqual(question);
  });
});

describe("visible completion bounds", () => {
  it("shows authoritative range, single-word and lower-only bounds without exposing keys", () => {
    const range = publicQuestion(bounded(3, 6));
    expect(range.instruction).toBe("Complete the sentence. Use 3 to 6 words.");
    expect(publicQuestion(bounded(undefined, 1)).instruction).toBe(
      "Complete the sentence. Use exactly 1 word.",
    );
    expect(publicQuestion(bounded(3, null)).instruction).toBe(
      "Complete the sentence. Use at least 3 words.",
    );
    expect(publicQuestion(bounded(1, null)).instruction).toBe(
      "Complete the sentence. Use at least 1 word.",
    );
    expect(publicQuestion(bounded(undefined, null)).instruction).toBe(
      "Complete the sentence.",
    );
    expect("acceptedAnswers" in range).toBe(false);
    expect("marking" in range).toBe(false);
  });

  it.each(["instruction", "prompt", "material"] as const)(
    "does not duplicate equivalent authored bounds in %s",
    (field) => {
      const q = bounded(3, 6);
      q[field] = "Write between three and six words.";
      expect(publicQuestion(q).instruction).toBe(q.instruction);
    },
  );

  it("retains an already authored one-word direction and does not mutate it", () => {
    const q = bounded(undefined, 1);
    q.instruction = "Write one word per gap.";
    const before = contentHash(q);
    expect(publicQuestion(q).instruction).toBe(q.instruction);
    expect(contentHash(q)).toBe(before);
  });
});
