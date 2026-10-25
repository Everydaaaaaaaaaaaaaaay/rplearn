import { readFileSync } from "node:fs";
import { z } from "zod";
import type { LearningQuestion } from "./content.js";
import { contentHash } from "./content-hash.js";

const ruleSchema = z.strictObject({
  instruction: z
    .string()
    .min(1)
    .max(420)
    .refine((s) => !/\p{Script=Han}/u.test(s)),
  sourceDirections: z.string(),
  removePrefix: z.string(),
  bindings: z.array(z.string().regex(/^[a-f0-9]{64}$/)).min(1),
});
const schema = z.strictObject({
  version: z.literal(1),
  reviewNotes: z.string(),
  rules: z.array(ruleSchema),
});
let rules: Map<string, z.infer<typeof ruleSchema>> | undefined;

/** Bind the full private question and the effective material, including group fallback.
 * Composed question IDs may differ; changed answers, rules or prose must not match.
 */
export function practiceDirectionSourceHash(
  question: LearningQuestion,
  material: string,
) {
  const source = { ...question };
  Reflect.deleteProperty(source, "id");
  return contentHash({ question: source, material });
}

/** Presentation only: frozen attempts, answer identities and marking remain untouched. */
export function practiceDirections(question: LearningQuestion, material: string) {
  if (!rules) {
    const registry = schema.parse(
      JSON.parse(
        readFileSync(
          new URL("../../../config/learning/practice-directions.json", import.meta.url),
          "utf8",
        ),
      ) as unknown,
    );
    rules = new Map();
    for (const rule of registry.rules)
      for (const binding of rule.bindings) {
        if (rules.has(binding)) throw new Error("Duplicate practice direction binding");
        rules.set(binding, rule);
      }
  }
  const rule = rules.get(practiceDirectionSourceHash(question, material));
  if (!rule) return undefined;
  if (!material.startsWith(rule.removePrefix))
    throw new Error("Practice direction material mismatch");
  return {
    instruction: rule.instruction,
    material: material.slice(rule.removePrefix.length).trimStart(),
  };
}
