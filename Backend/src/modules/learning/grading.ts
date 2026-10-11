import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import {
  clozeFillSchema,
  clozeSlotIds,
  listeningAnswerWordCount,
  type LearningQuestion,
} from "./content.js";

export const answerSchema = z.discriminatedUnion("kind", [
  z.strictObject({ kind: z.literal("choice"), optionId: z.string().min(1).max(120) }),
  z.strictObject({
    kind: z.literal("arrange"),
    tokenIds: z.array(z.string().min(1).max(120)).max(18),
  }),
  z.strictObject({ kind: z.literal("text"), text: z.string().max(1000) }),
  z.strictObject({ kind: z.literal("cloze"), fills: z.array(clozeFillSchema).max(6) }),
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
  pairResults?: readonly { left: string; correct: boolean }[];
  slotResults?: readonly { slotId: string; correct: boolean }[];
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
  let pairResults: GradeResult["pairResults"];
  let slotResults: GradeResult["slotResults"];
  const skipped = answer.kind === "skip";
  switch (question.type) {
    case "cloze": {
      const slots = clozeSlotIds(question.passage);
      const fills = answer.kind === "cloze" ? answer.fills : [];
      if (
        !skipped &&
        (answer.kind !== "cloze" ||
          new Set(fills.map((fill) => fill.slotId)).size !== fills.length ||
          new Set(fills.map((fill) => fill.tokenId)).size !== fills.length ||
          fills.some(
            (fill) =>
              !slots.includes(fill.slotId) ||
              !question.tokens.some((token) => token.id === fill.tokenId),
          ))
      )
        malformed();
      const matches = (expected: { slotId: string; tokenId: string }) =>
        fills.some(
          (fill) =>
            fill.slotId === expected.slotId && fill.tokenId === expected.tokenId,
        );
      // 多个完整可接受组合时，反馈对应最接近的合法组合，不拼出未获认可的新答案。
      const expected =
        [...question.acceptedFills].sort(
          (a, b) => b.filter(matches).length - a.filter(matches).length,
        )[0] ?? [];
      solution = { kind: "cloze", fills: expected };
      slotResults = slots.map((slotId) => ({
        slotId,
        correct:
          !skipped && expected.some((fill) => fill.slotId === slotId && matches(fill)),
      }));
      correct =
        fills.length === slots.length && slotResults.every((slot) => slot.correct);
      break;
    }
    case "choice":
    case "audioChoice":
    case "listeningChoice": {
      solution = { kind: "choice", optionId: question.answer };
      if (!skipped) {
        if (
          answer.kind !== "choice" ||
          !(
            question.type === "audioChoice" ? question.audioOptions : question.options
          ).some((o) => o.id === answer.optionId)
        )
          malformed();
        correct = answer.optionId === question.answer;
      }
      break;
    }
    case "arrange":
    case "audioArrange": {
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
    case "listeningCompletion":
    case "dictation": {
      solution = { kind: "text", text: question.acceptedAnswers[0] ?? "" };
      if (!skipped) {
        if (answer.kind !== "text") malformed();
        correct =
          (question.type !== "listeningCompletion" ||
            listeningAnswerWordCount(answer.text) <= question.wordLimit) &&
          question.acceptedAnswers.some(
            (expected) =>
              normalize(expected, question.normalization) ===
              normalize(answer.text, question.normalization),
          );
      }
      break;
    }
    case "audioMatching":
    case "matching": {
      const left =
        question.type === "audioMatching" ? question.audioOptions : question.left;
      solution = { kind: "matching", pairs: question.answerPairs };
      if (question.type === "audioMatching")
        pairResults = question.answerPairs.map((expected) => ({
          left: expected.left,
          correct:
            answer.kind === "matching" &&
            answer.pairs.some(
              (pair) => pair.left === expected.left && pair.right === expected.right,
            ),
        }));
      if (!skipped) {
        if (
          answer.kind !== "matching" ||
          new Set(answer.pairs.map((p) => p.left)).size !== answer.pairs.length ||
          new Set(answer.pairs.map((p) => p.right)).size !== answer.pairs.length ||
          answer.pairs.some(
            (p) =>
              !left.some((o) => o.id === p.left) ||
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
    ...(slotResults ? { slotResults } : {}),
    ...(pairResults ? { pairResults } : {}),
  };
}
