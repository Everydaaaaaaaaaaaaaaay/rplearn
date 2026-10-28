import { describe, expect, it, vi } from "vitest";
import { initialRoundQuestionIds } from "../../../src/modules/learning/round-order.js";

const picture = {
  originalGroup: { family: "word_picture_matching" },
  questions: ["cup", "ball", "book", "pencil"].map((id) => ({
    id,
    type: "choice" as const,
  })),
};

describe("initial independent picture matching order", () => {
  it("uses the draw to vary the complete question set without changing the source", () => {
    const before = structuredClone(picture);
    const rotated = initialRoundQuestionIds(picture, () => 0);
    const another = initialRoundQuestionIds(picture, (upper) => upper - 1);
    expect(rotated).toEqual(["ball", "book", "pencil", "cup"]);
    expect(another).toEqual(["cup", "ball", "book", "pencil"]);
    expect(new Set(rotated)).toEqual(new Set(picture.questions.map((q) => q.id)));
    expect(picture).toEqual(before);
  });

  it.each([
    "reading_choice",
    "choice_cloze",
    "shared_insertion",
    "dialogue_matching",
    "grammar_choice_cloze",
  ])("keeps dependent %s input in its authored order", (family) => {
    const draw = vi.fn(() => 0);
    expect(
      initialRoundQuestionIds({ ...picture, originalGroup: { family } }, draw),
    ).toEqual(picture.questions.map((q) => q.id));
    expect(draw).not.toHaveBeenCalled();
  });

  it("keeps other interactions and non-group questions in their existing order", () => {
    const draw = vi.fn(() => 0);
    const mixed = {
      ...picture,
      questions: [...picture.questions, { id: "text", type: "completion" as const }],
    };
    expect(initialRoundQuestionIds(mixed, draw)).toEqual(
      mixed.questions.map((q) => q.id),
    );
    expect(initialRoundQuestionIds({ questions: picture.questions }, draw)).toEqual(
      picture.questions.map((q) => q.id),
    );
    expect(
      initialRoundQuestionIds({ ...picture, originalGroup: undefined }, draw),
    ).toEqual(picture.questions.map((q) => q.id));
    expect(draw).not.toHaveBeenCalled();
  });
});
