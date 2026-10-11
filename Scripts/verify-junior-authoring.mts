import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  questionSchema,
  publicUnit,
  unitSchema,
} from "../Backend/src/modules/learning/content.ts";
import {
  answerSchema,
  gradeAnswer,
} from "../Backend/src/modules/learning/grading.ts";
import { learningFixture } from "../Backend/test/helpers/learning.ts";

// 只把人工草稿投影到内存测试夹具；不生成教学内容、媒体或正式单元文件。
const directory = new URL("../Backend/config/learning/", import.meta.url);
const registry = JSON.parse(
  await readFile(new URL("catalog.json", directory), "utf8"),
);
const goals = new Map(registry.goals.map((g) => [g.id, g.level]));
const sources = new Set(registry.sources.map((s) => s.id));
const normalize = (value: string) =>
  value
    .toLowerCase()
    .replace(/[.,!?;:]/g, "")
    .replace(/\s+/g, " ")
    .trim();
let positives = 0,
  negatives = 0,
  competingAudio = 0;
const reports = [];
for (const level of ["junior1", "junior2", "junior3"]) {
  const draft = JSON.parse(
    await readFile(new URL(`authoring/${level}.astra.json`, directory), "utf8"),
  );
  assert.equal(draft.questions.length, 36);
  assert.equal(new Set(draft.questions.map((q) => q.id)).size, 36);
  assert.equal(draft.openingStories.length, 2);
  const questions = draft.questions.map((q) => {
    assert.equal(goals.get(q.goalId), level, `${q.id} 目标与年级不符`);
    assert(
      sources.has(q.sourceId ?? q.source?.split(" ")[0]),
      `${q.id} 引用来源未登记`,
    );
    const common = {
      id: q.id,
      goalId: q.goalId,
      type: q.type,
      instruction: q.instruction ?? "仅供内存合同核验，不作正式教学指令。",
      prompt: q.prompt,
      hint: q.hint,
      explanation: q.explanation,
      difficultyReason: q.difficulty ?? q.review.difficulty,
    };
    const audio = q.audioScript
      ? { assetId: "test.pending-audio", text: q.audioScript, voice: "test" }
      : undefined;
    const fields =
      q.type === "choice" || q.type === "listeningChoice"
        ? { options: q.options, answer: q.answer }
        : q.type === "arrange" || q.type === "audioArrange"
          ? { tokens: q.tokens, acceptedOrders: q.acceptedOrders }
          : q.type === "matching"
            ? {
                left: q.left,
                right: q.right,
                answerPairs: q.answerPairs.map(([left, right]) => ({
                  left,
                  right,
                })),
              }
            : {
                acceptedAnswers: [q.answer, ...q.acceptedVariants],
                normalization: {
                  ignoreCase: true,
                  ignoreTerminalPunctuation: true,
                },
              };
    const question = questionSchema.parse({
      ...common,
      ...fields,
      ...(audio ? { audio } : {}),
    });
    const positive =
      "acceptedAnswers" in question
        ? question.acceptedAnswers.map((text) => ({ kind: "text", text }))
        : "acceptedOrders" in question
          ? question.acceptedOrders.map((tokenIds) => ({
              kind: "arrange",
              tokenIds,
            }))
          : "answerPairs" in question
            ? [{ kind: "matching", pairs: question.answerPairs }]
            : [{ kind: "choice", optionId: question.answer }];
    for (const answer of positive) {
      assert.equal(
        gradeAnswer(question, answerSchema.parse(answer)).outcome,
        "correct",
        q.id,
      );
      positives++;
    }
    const wrong = q.review.wrongExample;
    assert.equal(typeof wrong, "string", `${q.id} 缺少反例`);
    const wrongAnswer =
      "acceptedAnswers" in question
        ? { kind: "text", text: wrong }
        : "acceptedOrders" in question
          ? { kind: "arrange", tokenIds: wrong.split(",") }
          : "answerPairs" in question
            ? {
                kind: "matching",
                pairs: wrong.split(",").map((pair) => {
                  const [left, right] = pair.split("-");
                  return { left, right };
                }),
              }
            : { kind: "choice", optionId: wrong };
    assert.equal(
      gradeAnswer(question, answerSchema.parse(wrongAnswer)).outcome,
      "incorrect",
      q.id,
    );
    negatives++;
    if (question.type === "audioArrange") {
      for (const order of question.acceptedOrders) {
        const text = order
          .map((id) => question.tokens.find((t) => t.id === id)!.text)
          .join(" ");
        assert.equal(
          normalize(text),
          normalize(q.audioScript),
          `${q.id} 词块答案不还原录音`,
        );
      }
      if (
        question.acceptedOrders.some(
          (order) => order.length < question.tokens.length,
        )
      )
        competingAudio++;
    }
    return question;
  });
  for (let start = 0; start < 36; start += 18) {
    const group = questions.slice(start, start + 18);
    const fixture = unitSchema.parse({
      ...learningFixture(),
      level,
      questions: group,
      goalIds: [...new Set(group.map((q) => q.goalId))],
    });
    for (const q of publicUnit(fixture).questions) {
      for (const key of [
        "answer",
        "acceptedAnswers",
        "acceptedOrders",
        "answerPairs",
        "explanation",
      ])
        assert(!(key in q));
      if ("audio" in q) assert(!("text" in q.audio));
    }
  }
  reports.push({
    level,
    questions: questions.length,
    audioScripts: draft.questions.filter((q) => q.audioScript).length,
    types: [...new Set(questions.map((q) => q.type))],
  });
}
console.log(
  JSON.stringify({
    reports,
    positives,
    negatives,
    competingAudio,
    scope:
      "隔离草稿合同与判题核验；不证明语义、音频制作、原生体验、正式去重或上线",
  }),
);
