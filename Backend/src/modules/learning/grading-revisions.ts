import { readFileSync } from "node:fs";
import { z } from "zod";
import type { LearningQuestion } from "./content.js";
import { contentHash } from "./content-hash.js";

const entrySchema = z.strictObject({
  sourceHash: z.string().regex(/^[a-f0-9]{64}$/),
  sourceUnitId: z.string(),
  sourceQuestionId: z.string(),
  reviewedSourceSHA256: z.string().regex(/^[a-f0-9]{64}$/),
  acceptedAnswers: z.array(z.string().min(1).max(600)).min(1).max(64),
  rejectedAnswers: z.array(z.string().max(600)).max(100),
  explanation: z.string().min(20).max(8000),
});
const registrySchema = z.strictObject({
  version: z.literal(1),
  reviewedAt: z.iso.date(),
  reviewNotes: z.string().min(30),
  entries: z.array(entrySchema).max(200),
});
let revisions: Map<string, z.infer<typeof entrySchema>> | undefined;
function registry() {
  if (!revisions) {
    const value = registrySchema.parse(
      JSON.parse(
        readFileSync(
          new URL("../../../config/learning/grading-revisions.json", import.meta.url),
          "utf8",
        ),
      ) as unknown,
    );
    revisions = new Map(value.entries.map((entry) => [entry.sourceHash, entry]));
    if (
      revisions.size !== value.entries.length ||
      value.entries.some((entry) =>
        entry.rejectedAnswers.some((answer) => entry.acceptedAnswers.includes(answer)),
      )
    )
      throw new Error(
        "Reviewed grading revisions contain duplicate or conflicting identities",
      );
  }
  return revisions;
}

/** Only remapped local/bank IDs are excluded; every other frozen field must match. */
export function gradingSourceHash(question: LearningQuestion) {
  const source = { ...question };
  Reflect.deleteProperty(source, "id");
  return contentHash(source);
}

/** Effective evaluation only: never persist this copy over a snapshot or old result. */
export function questionForGrading(question: LearningQuestion): LearningQuestion {
  if (question.type !== "completion") return question;
  const revision = registry().get(gradingSourceHash(question));
  if (!revision) return question;
  if (!question.marking)
    throw new Error("Reviewed completion revision lacks its frozen marking contract");
  return {
    ...question,
    acceptedAnswers: [...revision.acceptedAnswers],
    marking: { ...question.marking, rejectedAnswers: [...revision.rejectedAnswers] },
    explanation: revision.explanation,
  };
}
