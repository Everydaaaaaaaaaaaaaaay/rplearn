import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import type { LearningQuestion } from "./content.js";

export const answerSchema = z.discriminatedUnion("kind", [
  z.strictObject({ kind: z.literal("choice"), optionId: z.string().min(1).max(120) }),
  z.strictObject({
    kind: z.literal("arrange"),
    tokenIds: z.array(z.string().min(1).max(120)).max(18),
  }),
  z.strictObject({ kind: z.literal("text"), text: z.string().max(1000) }),
  z.strictObject({
    kind: z.literal("matching"),
    pairs: z
      .array(z.strictObject({ left: z.string().max(120), right: z.string().max(120) }))
      .max(5),
  }),
  z.strictObject({ kind: z.literal("skip") }),
]);
export type LearningAnswer = z.infer<typeof answerSchema>;
export type GradeResult = Readonly<{
  outcome: "correct" | "incorrect" | "skipped";
  explanation: string;
  solution: LearningAnswer;
}>;

function normalize(
  text: string,
  rule: { ignoreCase: boolean; ignoreTerminalPunctuation: boolean },
): string {
  let value = text.normalize("NFC").trim().replace(/\s+/gu, " ").replace(/[’‘]/gu, "'");
  if (rule.ignoreCase) value = value.toLocaleLowerCase("en-US");
  if (rule.ignoreTerminalPunctuation)
    value = value.replace(/[.!?。！？]+$/gu, "").trim();
  return value;
}

function malformed(): never {
  throw new AppError({
    code: "LEARNING_INVALID_ANSWER",
    message: "答案格式或选项与这道题不匹配。",
    statusCode: 400,
  });
}

export function gradeAnswer(
  question: LearningQuestion,
  answer: LearningAnswer,
): GradeResult {
  let correct = false;
  let solution: LearningAnswer;
  const skipped = answer.kind === "skip";
  switch (question.type) {
    case "choice":
    case "listeningChoice": {
      solution = { kind: "choice", optionId: question.answer };
      if (!skipped) {
        if (
          answer.kind !== "choice" ||
          !question.options.some((o) => o.id === answer.optionId)
        )
          malformed();
        correct = answer.optionId === question.answer;
      }
      break;
    }
    case "arrange": {
      solution = { kind: "arrange", tokenIds: question.acceptedOrders[0] ?? [] };
      if (!skipped) {
        if (
          answer.kind !== "arrange" ||
          new Set(answer.tokenIds).size !== answer.tokenIds.length ||
          answer.tokenIds.some(
            (id) => !question.tokens.some((token) => token.id === id),
          )
        )
          malformed();
        correct = question.acceptedOrders.some(
          (order) =>
            order.length === answer.tokenIds.length &&
            order.every((id, i) => id === answer.tokenIds[i]),
        );
      }
      break;
    }
    case "completion":
    case "dictation": {
      solution = { kind: "text", text: question.acceptedAnswers[0] ?? "" };
      if (!skipped) {
        if (answer.kind !== "text") malformed();
        correct = question.acceptedAnswers.some(
          (expected) =>
            normalize(expected, question.normalization) ===
            normalize(answer.text, question.normalization),
        );
      }
      break;
    }
    case "matching": {
      solution = { kind: "matching", pairs: question.answerPairs };
      if (!skipped) {
        if (
          answer.kind !== "matching" ||
          new Set(answer.pairs.map((p) => p.left)).size !== answer.pairs.length ||
          new Set(answer.pairs.map((p) => p.right)).size !== answer.pairs.length ||
          answer.pairs.some(
            (p) =>
              !question.left.some((o) => o.id === p.left) ||
              !question.right.some((o) => o.id === p.right),
          )
        )
          malformed();
        correct =
          answer.pairs.length === question.answerPairs.length &&
          question.answerPairs.every((expected) =>
            answer.pairs.some(
              (pair) => pair.left === expected.left && pair.right === expected.right,
            ),
          );
      }
      break;
    }
  }
  return {
    outcome: skipped ? "skipped" : correct ? "correct" : "incorrect",
    explanation: question.explanation,
    solution,
  };
}
