import { readFile, readdir } from "node:fs/promises";
import { describe, expect, it } from "vitest";
import {
  contentHash,
  publicQuestion,
  publicUnit,
  unitSchema,
} from "../../../src/modules/learning/content.js";
import {
  hasAppropriateQuestionLanguage,
  presentationSourceHash,
  questionForPresentation,
} from "../../../src/modules/learning/presentation.js";
import { questionListeningScript } from "../../../src/modules/learning/listening-speech.js";
import { gradeAnswer } from "../../../src/modules/learning/grading.js";
import { availableForNewLearning } from "../../../src/modules/learning/bank-content.js";

const load = async (path: string) =>
  JSON.parse(await readFile(path, "utf8")) as unknown;
const directory = "config/learning";
const unit = async (id: string) =>
  unitSchema.parse(await load(`${directory}/units/${id}.json`));

describe("reviewed learning question language", () => {
  it("corrects the exact old book-swap snapshot and its spoken question without changing grading", async () => {
    const current = await unit("companion.senior3.paper-boat");
    const original = current.questions[0];
    if (original?.type !== "listeningChoice") throw new Error("Missing fixture");
    // This is the released v1 question, including its original private fields.
    const old = {
      ...original,
      prompt: "听两人商量旧书交换活动。第二位说话人最后支持什么安排？",
      options: [
        { id: "a", text: "取消活动，因为下午也缺少帮手。" },
        { id: "b", text: "保留活动，建议改到午饭后进行。" },
        { id: "c", text: "保留活动，仍按周六上午安排。" },
      ],
    };
    const before = contentHash(old);
    const shown = publicQuestion(old);
    expect(shown.prompt).toBe(original.prompt);
    expect("options" in shown && shown.options).toEqual(original.options);
    expect(availableForNewLearning(old, "senior3")).toBe(true);
    const script = await questionListeningScript(old, old.audio.assetId);
    expect(script?.segments.at(-1)?.text).toBe(`Question: ${original.prompt}`);
    expect(script?.segments[0]?.pauseAfterMs).toBe(3000);
    for (const id of ["a", "b", "c"])
      expect(gradeAnswer(old, { kind: "choice", optionId: id })).toEqual(
        gradeAnswer(original, { kind: "choice", optionId: id }),
      );
    expect(contentHash(old)).toBe(before);
    expect(JSON.stringify(shown)).not.toContain(old.audio.text);
    expect(shown).not.toHaveProperty("answer");
  });

  it("matches composed IDs but refuses a reused ID with changed answer or material", async () => {
    const source = (await unit("companion.senior3.folded-page")).questions[0];
    if (source?.type !== "choice") throw new Error("Missing fixture");
    expect(presentationSourceHash({ ...source, id: "question.bank-hash" })).toBe(
      presentationSourceHash(source),
    );
    expect(publicQuestion({ ...source, id: "question.bank-hash" }).prompt).not.toMatch(
      /\p{Script=Han}/u,
    );
    const altered = { ...source, answer: source.answer === "a" ? "b" : "a" };
    expect(questionForPresentation(altered)).toBe(altered);
    const other = { ...source, material: "A different passage." };
    expect(questionForPresentation(other)).toBe(other);
  });

  it("audits every curated question and all 5090 original-group responses", async () => {
    let curated = 0;
    for (const file of await readdir(`${directory}/units`)) {
      if (!file.endsWith(".json")) continue;
      const source = unitSchema.parse(await load(`${directory}/units/${file}`));
      const before = contentHash(source);
      const shown = publicUnit(source);
      for (const q of source.questions) {
        curated++;
        expect(
          hasAppropriateQuestionLanguage(q, source.level),
          `${source.id}/${q.id}`,
        ).toBe(true);
        const view = shown.questions.find((p) => p.id === q.id);
        expect(view).not.toHaveProperty("answer");
        if (q.type === "choice" || q.type === "listeningChoice") {
          expect(view && "options" in view && view.options.map((o) => o.id)).toEqual(
            q.options.map((o) => o.id),
          );
          expect(questionForPresentation(q)).toMatchObject({
            answer: q.answer,
            goalId: q.goalId,
          });
        }
      }
      expect(contentHash(source)).toBe(before);
    }
    const originals = (await load(`${directory}/originals/catalog.json`)) as {
      units: { unit: unknown }[];
    };
    let responses = 0;
    for (const entry of originals.units) {
      const source = unitSchema.parse(entry.unit);
      for (const q of source.questions) {
        responses++;
        expect(
          hasAppropriateQuestionLanguage(q, source.level),
          `${source.id}/${q.id}`,
        ).toBe(true);
      }
    }
    expect(curated).toBe(738);
    expect(responses).toBe(5090);
    const revisions = (await load(
      `${directory}/bank-revisions/2026-10-11-cross-question.json`,
    )) as {
      updates: { question: { level: string; question: unknown } }[];
    };
    for (const update of revisions.updates) {
      const q = unitSchema.shape.questions.element.parse(update.question.question);
      expect(hasAppropriateQuestionLanguage(q, update.question.level), q.id).toBe(true);
    }
  });

  it("retains purposeful Chinese scaffolding and translations, and rejects new unreviewed Chinese choices", async () => {
    const early = await unit("oliver.primary1.reading-bag");
    expect(publicUnit(early).questions[0]?.prompt).toMatch(/\p{Script=Han}/u);
    const matching = (await unit("oliver.junior1.lost-found-desk")).questions.find(
      (q) => q.type === "matching",
    );
    expect(matching && questionForPresentation(matching)).toBe(matching);
    const q = (await unit("companion.senior3.paper-boat")).questions[0];
    if (!q) throw new Error("Missing fixture");
    expect(
      availableForNewLearning({ ...q, prompt: "一条新的未审中文题干？" }, "senior3"),
    ).toBe(false);
  });
});
