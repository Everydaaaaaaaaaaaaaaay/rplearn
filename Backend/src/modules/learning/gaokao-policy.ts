import { readFileSync } from "node:fs";
import { z } from "zod";
import { contentHash, unitSchema, type LearningUnit } from "./content.js";
import { expansionGaokaoPractices } from "./expansion-catalog.js";

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
  sourceNumbers: z.array(z.number().int().min(1).max(65)).min(3).max(20),
  sourceUnitId: z.string().optional(),
  sourceContentHash: z
    .string()
    .regex(/^[a-f0-9]{64}$/)
    .optional(),
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
        kind: z.enum(["past-paper", "authored"]).default("past-paper"),
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
  const authored = z
    .strictObject({
      version: z.literal(1),
      standard: z.literal("gaokao.2025.national1"),
      notice: z.string(),
      practices: catalogSchema.shape.practices,
    })
    .parse(
      JSON.parse(
        readFileSync(
          new URL("../../../config/learning/gaokao/authored.json", import.meta.url),
          "utf8",
        ),
      ),
    );
  if (authored.practices.some((p) => p.kind !== "authored"))
    throw new Error("原创题不得冒充高考真题。");
  parsed.practices.push(...authored.practices);
  parsed.practices.push(...expansionGaokaoPractices());
  const ids = new Set<string>();
  for (const p of parsed.practices) {
    const u = p.unit;
    const families = p.components.map((c) => c.family).join("+");
    const count = u.questions.length;
    const validWorkload =
      (families === "choice_cloze" && (count === 15 || count === 20)) ||
      (families === "reading_choice+reading_choice" && count >= 6 && count <= 8) ||
      (families === "shared_insertion+passage_form" && count === 15) ||
      (families === "reading_choice+shared_insertion" && (count === 8 || count === 9));
    if (
      ids.has(u.id) ||
      !isHighSchool(u.level) ||
      !u.originalGroup ||
      u.beats.length ||
      contentHash(u) !== p.contentHash ||
      !validWorkload ||
      u.estimatedMinutes < 14 ||
      u.estimatedMinutes > (p.kind === "authored" ? 20 : 18) ||
      contentHash(p.components.flatMap((c) => c.questionIds)) !==
        contentHash(u.questions.map((q) => q.id)) ||
      p.components.some((c) => c.questionIds.length !== c.sourceNumbers.length) ||
      (p.kind === "authored" &&
        (!u.title.startsWith("高考题型原创") ||
          !u.originalGroup.sourceNotice.includes("非高考真题") ||
          contentHash(u.originalGroup.sourceGroupIds) !==
            contentHash(p.components.map((c) => c.id)) ||
          p.components.some(
            (c) =>
              !c.sourceUnitId ||
              !c.sourceContentHash ||
              !c.id.startsWith(c.sourceUnitId + "#"),
          ))) ||
      p.components.some((c) => {
        const qs = u.questions.filter((q) => c.questionIds.includes(q.id));
        if (qs.some((q) => q.material !== qs[0]?.material)) return true;
        if (c.family === "choice_cloze")
          return (
            ![15, 20].includes(qs.length) ||
            qs.some((q) => q.type !== "choice" || q.options.length !== 4)
          );
        if (c.family === "reading_choice")
          return (
            ![3, 4].includes(qs.length) ||
            qs.some((q) => q.type !== "choice" || q.options.length !== 4)
          );
        if (c.family === "shared_insertion")
          return (
            qs.length !== 5 ||
            qs.some((q) => q.type !== "choice" || q.options.length !== 7)
          );
        return (
          qs.length !== 10 || qs.some((q) => q.type !== "completion" || !q.marking)
        );
      }) ||
      u.questions.some((q) => !q.material || !["choice", "completion"].includes(q.type))
    )
      throw new Error(`高考题型准入审核或完整组卷边界不符：${u.id}`);
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
