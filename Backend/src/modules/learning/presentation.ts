import { readFileSync } from "node:fs";
import { z } from "zod";
import type { LearningQuestion } from "./content.js";
import { contentHash } from "./content-hash.js";

const revisionSchema = z.strictObject({
  sourceHash: z.string().regex(/^[a-f0-9]{64}$/),
  sourceUnitId: z.string(),
  sourceQuestionId: z.string(),
  prompt: z
    .string()
    .min(1)
    .max(1200)
    .refine((s) => !/\p{Script=Han}/u.test(s)),
  options: z
    .array(
      z.strictObject({
        id: z.string(),
        text: z
          .string()
          .min(1)
          .max(1200)
          .refine((s) => !/\p{Script=Han}/u.test(s)),
      }),
    )
    .optional(),
});
const registrySchema = z.strictObject({
  version: z.literal(1),
  reviewedAt: z.string(),
  reviewNotes: z.string(),
  entries: z.array(revisionSchema).max(2000),
});
let revisions: Map<string, z.infer<typeof revisionSchema>> | undefined;
function registry() {
  if (!revisions) {
    const parsed = registrySchema.parse(
      JSON.parse(
        readFileSync(
          new URL(
            "../../../config/learning/presentation-revisions.json",
            import.meta.url,
          ),
          "utf8",
        ),
      ) as unknown,
    );
    revisions = new Map(parsed.entries.map((entry) => [entry.sourceHash, entry]));
    if (revisions.size !== parsed.entries.length)
      throw new Error("学习题面修订包含重复内容身份。");
  }
  return revisions;
}

/** Local IDs become bank IDs when composed; every other frozen field must match. */
export function presentationSourceHash(question: LearningQuestion) {
  const source = { ...question };
  Reflect.deleteProperty(source, "id");
  return contentHash(source);
}

/** Display copy only. Never use this value for grading or persist it over a snapshot.
 * Exact full-content bindings prevent a translation reaching a different question,
 * changed answer, media asset or administrator revision with a reused local ID.
 */
export function questionForPresentation(question: LearningQuestion): LearningQuestion {
  const revision = registry().get(presentationSourceHash(question));
  if (!revision) return question;
  if (question.type !== "choice" && question.type !== "listeningChoice")
    throw new Error("题面修订只能更改已审核选择题。");
  const options = question.options.map((option) => {
    if (!revision.options) return option;
    const replacement = revision.options.find((item) => item.id === option.id);
    if (!replacement) throw new Error("题面修订缺少原选项身份。");
    return { ...option, text: replacement.text };
  });
  if (revision.options && revision.options.length !== options.length)
    throw new Error("题面修订不能增减选项。");
  return { ...question, prompt: revision.prompt, options };
}

/** Chinese is appropriate for translations, word pools and primary scaffolding.
 * Secondary/adult choices test English comprehension, including English glosses.
 */
export function hasAppropriateQuestionLanguage(
  question: LearningQuestion,
  level: string,
) {
  const shown = questionForPresentation(question);
  if (!/^(junior[123]|senior[123]|undergraduate|postgraduate|advanced)$/.test(level))
    return true;
  if (shown.type !== "choice" && shown.type !== "listeningChoice") return true;
  // Gap numbers and questions deliberately spoken in the recording are directions.
  const directionOnly =
    /^(?:(?:[A-Z]篇 · )?第\d+空(?:（\d+分）)?|第\d+句空|第\d+处(?:：选择一整个段落)?|第\d+题（问题在录音中）)$/.test(
      shown.prompt,
    );
  // Explicit English-to-Chinese vocabulary questions genuinely need Chinese choices.
  const translation = /\bmean in Chinese\?$/i.test(shown.prompt);
  return (
    (directionOnly || !/\p{Script=Han}/u.test(shown.prompt)) &&
    (translation ||
      shown.options.every(
        (o) => o.imageAssetId !== undefined || !/\p{Script=Han}/u.test(o.text),
      ))
  );
}
