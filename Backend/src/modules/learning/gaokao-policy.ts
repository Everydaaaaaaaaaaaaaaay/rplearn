import { readFileSync } from "node:fs";
import { z } from "zod";
import { contentHash, unitSchema, type LearningUnit } from "./content.js";

export const isHighSchool = (level: string) => /^senior[123]$/.test(level);

const componentSchema = z.strictObject({
  id: z.string().min(1),
  family: z.enum([
    "reading_choice",
    "choice_cloze",
    "shared_insertion",
    "passage_form",
  ]),
  questionIds: z.array(z.string()).min(3).max(20),
  sourceNumbers: z.array(z.number().int().min(21).max(65)).min(3).max(20),
});
const catalogSchema = z.strictObject({
  version: z.literal(1),
  source: z.strictObject({
    id: z.string(),
    year: z.number().int(),
    paper: z.string(),
    url: z.url(),
    sha256: z.string().regex(/^[a-f0-9]{64}$/),
    identityEvidenceURL: z.url(),
    numberingEvidenceURL: z.url(),
    numbering: z.string(),
    scope: z.string(),
  }),
  practices: z
    .array(
      z.strictObject({
        unit: unitSchema,
        contentHash: z.string().regex(/^[a-f0-9]{64}$/),
        components: z.array(componentSchema).min(1).max(2),
      }),
    )
    .min(1)
    .max(100),
});
let catalog: z.infer<typeof catalogSchema> | undefined;
/** A reviewed payload digest, not an arbitrary source label, grants admission. */
export function gaokaoCatalog() {
  if (catalog) return catalog;
  const parsed = catalogSchema.parse(
    JSON.parse(
      readFileSync(
        new URL("../../../config/learning/gaokao/catalog.json", import.meta.url),
        "utf8",
      ),
    ),
  );
  const ids = new Set<string>();
  for (const p of parsed.practices) {
    const u = p.unit;
    const families = p.components.map((c) => c.family).join("+");
    const count = u.questions.length;
    const validWorkload =
      (families === "choice_cloze" && (count === 15 || count === 20)) ||
      (families === "reading_choice+reading_choice" && count >= 6 && count <= 8) ||
      (families === "shared_insertion+passage_form" && count === 15);
    if (
      ids.has(u.id) ||
      !isHighSchool(u.level) ||
      !u.originalGroup ||
      u.beats.length ||
      contentHash(u) !== p.contentHash ||
      !validWorkload ||
      u.estimatedMinutes < 14 ||
      u.estimatedMinutes > 18 ||
      contentHash(p.components.flatMap((c) => c.questionIds)) !==
        contentHash(u.questions.map((q) => q.id)) ||
      p.components.some((c) => c.questionIds.length !== c.sourceNumbers.length) ||
      u.questions.some((q) => !q.material || !["choice", "completion"].includes(q.type))
    )
      throw new Error(`高考真题审核或完整组卷边界不符：${u.id}`);
    ids.add(u.id);
  }
  catalog = parsed;
  return parsed;
}
export function gaokaoUnitIds() {
  return gaokaoCatalog().practices.map((p) => p.unit.id);
}
export function isAdmittedGaokaoUnit(unit: LearningUnit): boolean {
  return gaokaoCatalog().practices.some(
    (p) => p.unit.id === unit.id && p.contentHash === contentHash(unit),
  );
}
