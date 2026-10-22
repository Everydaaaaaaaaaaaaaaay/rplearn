import { z } from "zod";
import { gradeAnswer } from "../../../src/modules/learning/grading.js";
import { readFile } from "node:fs/promises";
import { describe, expect, it } from "vitest";
import { questionListeningScript } from "../../../src/modules/learning/listening-speech.js";
import {
  publicQuestion,
  questionSchema,
} from "../../../src/modules/learning/content.js";
import { availableForNewLearning } from "../../../src/modules/learning/bank-content.js";

const question = questionSchema.parse({
  id: "test.listening",
  goalId: "test.goal",
  type: "listeningChoice",
  prompt: "Where can pupils ask for a rest?",
  instruction: "Listen and choose.",
  hint: "Listen to the discussion.",
  explanation: "The discussion concerns a rest area.",
  difficultyReason: "Listening for a detail.",
  options: [
    { id: "a", text: "At the desk." },
    { id: "b", text: "By phone." },
  ],
  answer: "a",
  audio: { assetId: "audio.test", text: "Pupils can ask at the desk.", voice: "F3" },
});
describe("live listening scripts", () => {
  it("keeps the spoken question separate after three seconds, with no answer leakage", async () => {
    expect(await questionListeningScript(question, "audio.test")).toEqual({
      assetId: "audio.test",
      segments: [
        { text: "Pupils can ask at the desk.", pauseAfterMs: 3000 },
        { text: "Question: Where can pupils ask for a rest?", pauseAfterMs: 0 },
      ],
    });
    expect(await questionListeningScript(question, "audio.another")).toBeUndefined();
    expect(JSON.stringify(publicQuestion(question))).not.toContain("Pupils can ask");
  });
  it("does not read Chinese directions into English synthesis", async () => {
    const early = { ...question, prompt: "听录音选图？" };
    expect((await questionListeningScript(early, "audio.test"))?.segments).toHaveLength(
      1,
    );
    expect(availableForNewLearning(early, "primary1")).toBe(true);
    expect(availableForNewLearning(early, "senior3")).toBe(false);
    expect(availableForNewLearning(question, "senior3")).toBe(true);
  });
  it("binds all 547 original tracks to a single material pass", async () => {
    const registry = z
      .object({
        assets: z.record(
          z.string(),
          z.object({ segments: z.array(z.object({ text: z.string() })) }),
        ),
      })
      .parse(
        JSON.parse(
          await readFile("config/learning/listening-scripts.json", "utf8"),
        ) as unknown,
      );
    const catalog = z
      .object({ audioAssets: z.array(z.object({ id: z.string() })) })
      .parse(
        JSON.parse(
          await readFile("config/learning/originals/catalog.json", "utf8"),
        ) as unknown,
      );
    expect(Object.keys(registry.assets).sort()).toEqual(
      catalog.audioAssets.map((a: { id: string }) => a.id).sort(),
    );
    for (const asset of Object.values(registry.assets)) {
      expect(asset.segments.length).toBeGreaterThan(0);
      expect(
        asset.segments.every(
          (s) =>
            !/^Now you will hear (?:the extract|the whole recording) again\.$/i.test(
              s.text,
            ),
        ),
      ).toBe(true);
    }
  });
});

it("retired dictation stays readable and gradeable but cannot enter fresh selection", () => {
  const legacy = questionSchema.parse({
    id: "test.old",
    type: "dictation",
    goalId: "test.goal",
    instruction: "Legacy history",
    prompt: "Write the sentence.",
    hint: "Legacy hint.",
    explanation: "Legacy explanation.",
    difficultyReason: "Legacy test.",
    audio: { assetId: "audio.test", text: "The door is open.", voice: "F3" },
    acceptedAnswers: ["The door is open."],
    normalization: { ignoreCase: true, ignoreTerminalPunctuation: true },
  });
  expect(availableForNewLearning(legacy, "senior3")).toBe(false);
  expect(gradeAnswer(legacy, { kind: "text", text: "The door is open." }).outcome).toBe(
    "correct",
  );
});
