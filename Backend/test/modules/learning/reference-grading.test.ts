import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import {
  contentHash,
  questionSchema,
  unitSchema,
  type LearningQuestion,
} from "../../../src/modules/learning/content.js";
import {
  gradeAnswer,
  type LearningAnswer,
} from "../../../src/modules/learning/grading.js";

const common = {
  id: "test.reference",
  goalId: "test.goal",
  instruction: "Complete the task.",
  prompt: "Engineering fixture only.",
  explanation: "Use the reference answer.",
  hint: "Read the task.",
  difficultyReason: "Not teaching content.",
};
const audio = { assetId: "test.audio", text: "Alpha beta.", voice: "test" };
const options = [
  { id: "alpha", text: "Alpha" },
  { id: "beta", text: "Beta" },
];
const completion = questionSchema.parse({
  ...common,
  type: "completion",
  acceptedAnswers: ["was written", "had been written"],
  normalization: { ignoreCase: true, ignoreTerminalPunctuation: false },
  marking: {
    protocol: "english_phrase_v1",
    rejectedAnswers: ["write"],
    maxWords: 3,
    unlisted: "review",
  },
});
const fixtures: { question: LearningQuestion; wrong: LearningAnswer }[] = [
  ...["choice", "listeningChoice"].map((type) => ({
    question: questionSchema.parse({
      ...common,
      type,
      options,
      answer: "alpha",
      ...(type === "listeningChoice" ? { audio } : {}),
    }),
    wrong: { kind: "choice" as const, optionId: "beta" },
  })),
  {
    question: questionSchema.parse({
      ...common,
      type: "audioChoice",
      audioOptions: options.map((o) => ({ id: o.id, audio })),
      answer: "alpha",
    }),
    wrong: { kind: "choice", optionId: "beta" },
  },
  ...["arrange", "audioArrange"].map((type) => ({
    question: questionSchema.parse({
      ...common,
      type,
      tokens: options,
      acceptedOrders: [["alpha", "beta"]],
      ...(type === "audioArrange" ? { audio } : {}),
    }),
    wrong: { kind: "arrange" as const, tokenIds: ["beta", "alpha"] },
  })),
  { question: completion, wrong: { kind: "text", text: "1" } },
  ...["dictation", "listeningCompletion"].map((type) => ({
    question: questionSchema.parse({
      ...common,
      type,
      audio,
      acceptedAnswers: ["Alpha beta"],
      normalization: { ignoreCase: true, ignoreTerminalPunctuation: true },
      ...(type === "listeningCompletion" ? { wordLimit: 2 } : {}),
    }),
    wrong: { kind: "text" as const, text: "123" },
  })),
  {
    question: questionSchema.parse({
      ...common,
      type: "cloze",
      passage: "{first} then {second}.",
      tokens: options,
      acceptedFills: [
        [
          { slotId: "first", tokenId: "alpha" },
          { slotId: "second", tokenId: "beta" },
        ],
      ],
    }),
    wrong: {
      kind: "cloze",
      fills: [
        { slotId: "first", tokenId: "beta" },
        { slotId: "second", tokenId: "alpha" },
      ],
    },
  },
  ...["matching", "audioMatching"].map((type) => ({
    question: questionSchema.parse({
      ...common,
      type,
      ...(type === "matching"
        ? { left: options }
        : { audioOptions: options.map((o) => ({ id: o.id, audio })) }),
      right: [
        {
          id: "one",
          text: "One",
          ...(type === "audioMatching" ? { imageAssetId: "image.one" } : {}),
        },
        {
          id: "two",
          text: "Two",
          ...(type === "audioMatching" ? { imageAssetId: "image.two" } : {}),
        },
        {
          id: "three",
          text: "Three",
          ...(type === "audioMatching" ? { imageAssetId: "image.three" } : {}),
        },
      ],
      answerPairs: [
        { left: "alpha", right: "one" },
        { left: "beta", right: "two" },
      ],
    }),
    wrong: {
      kind: "matching" as const,
      pairs: [
        { left: "alpha", right: "two" },
        { left: "beta", right: "one" },
      ],
    },
  })),
];

describe("reference-based marking keeps ordinary wrong answers in the learning flow", () => {
  it("covers every supported question type", () => {
    expect(new Set(fixtures.map((f) => f.question.type))).toEqual(
      new Set(questionSchema.options.map((schema) => schema.shape.type.value)),
    );
  });

  it.each(fixtures)(
    "$question.type returns reference feedback for wrong answers and skips",
    ({ question, wrong }) => {
      const before = contentHash(question);
      const result = gradeAnswer(question, wrong);
      expect(result.outcome).toBe("incorrect");
      expect(result.explanation).toBe(question.explanation);
      expect(gradeAnswer(question, result.solution).outcome).toBe("correct");
      expect(gradeAnswer(question, { kind: "skip" }).outcome).toBe("skipped");
      expect(contentHash(question)).toBe(before);
    },
  );

  it.each([
    "1",
    "123",
    "Ⅰ",
    "１２３",
    "writtened",
    "unknownword",
    "中文",
    "🙂",
    "!",
    "",
    "was writing",
    "was written extra",
  ])("completion marks %j against the reference without requiring review", (text) => {
    expect(gradeAnswer(completion, { kind: "text", text })).toMatchObject({
      outcome: "incorrect",
      solution: { kind: "text", text: "was written" },
    });
  });

  it("retains explicit accepted variants, normalization and legitimate numeric references", () => {
    for (const text of ["was written", " HAD  BEEN WRITTEN "])
      expect(gradeAnswer(completion, { kind: "text", text }).outcome).toBe("correct");
    const numeric = questionSchema.parse({
      ...completion,
      acceptedAnswers: ["1"],
      marking: {
        protocol: "source_excerpt_v1",
        rejectedAnswers: [],
        maxWords: 1,
        unlisted: "review",
      },
    });
    expect(gradeAnswer(numeric, { kind: "text", text: "１" }).outcome).toBe("correct");
  });

  it("reproduces the screenshot's frozen historical grammar question without changing its snapshot", () => {
    const manifest = JSON.parse(
      readFileSync(
        new URL(
          "../../../config/learning/expansions/2026-10-24/b133.json",
          import.meta.url,
        ),
        "utf8",
      ),
    ) as { entries: { unit: unknown }[] };
    const question = manifest.entries
      .flatMap((e) => unitSchema.parse(e.unit).questions)
      .find(
        (q) =>
          q.material?.includes("A letter in our fictional history exercise") &&
          q.prompt.includes("gap 1"),
      );
    if (!question) throw new Error("Missing screenshot question");
    const before = contentHash(question);
    const result = gradeAnswer(question, { kind: "text", text: "1" });
    expect(result.outcome).toBe("incorrect");
    expect(gradeAnswer(question, result.solution).outcome).toBe("correct");
    expect(contentHash(question)).toBe(before);
  });

  it("continues to reject malformed answer kinds and nonexistent option identities", () => {
    expect(() =>
      gradeAnswer(completion, { kind: "choice", optionId: "alpha" }),
    ).toThrow(expect.objectContaining({ code: "LEARNING_INVALID_ANSWER" }));
    const choice = fixtures[0]?.question;
    if (!choice) throw new Error("Missing choice fixture");
    expect(() =>
      gradeAnswer(choice, { kind: "choice", optionId: "not-a-real-option" }),
    ).toThrow(expect.objectContaining({ code: "LEARNING_INVALID_ANSWER" }));
  });

  it("marks valid partial arrangements, matching and cloze as incorrect instead of blocking", () => {
    for (const { question, wrong } of fixtures) {
      if (wrong.kind === "arrange") {
        for (const tokenIds of [[], wrong.tokenIds.slice(0, 1)])
          expect(gradeAnswer(question, { kind: "arrange", tokenIds }).outcome).toBe(
            "incorrect",
          );
      } else if (wrong.kind === "matching") {
        for (const pairs of [[], wrong.pairs.slice(0, 1)])
          expect(gradeAnswer(question, { kind: "matching", pairs }).outcome).toBe(
            "incorrect",
          );
      } else if (wrong.kind === "cloze") {
        for (const fills of [[], wrong.fills.slice(0, 1)])
          expect(gradeAnswer(question, { kind: "cloze", fills }).outcome).toBe(
            "incorrect",
          );
      }
    }
  });
});
