import { randomInt } from "node:crypto";
import type { LearningQuestion } from "./content.js";

type RoundOrderUnit = Readonly<{
  originalGroup?: Readonly<{ family: string }> | undefined;
  questions: readonly Pick<LearningQuestion, "id" | "type">[];
}>;

/** Shuffle independent word-to-picture prompts only, then freeze the result in the round. */
export function initialRoundQuestionIds(
  unit: RoundOrderUnit,
  draw: (upperExclusive: number) => number = (upper) => randomInt(upper),
): string[] {
  const ids = unit.questions.map((q) => q.id);
  if (
    unit.originalGroup?.family !== "word_picture_matching" ||
    !unit.questions.every((q) => q.type === "choice")
  )
    return ids;
  for (let index = ids.length - 1; index > 0; index--) {
    const target = draw(index + 1),
      current = ids[index],
      other = ids[target];
    if (current === undefined || other === undefined)
      throw new Error("Picture question shuffle index outside its round");
    ids[index] = other;
    ids[target] = current;
  }
  return ids;
}
