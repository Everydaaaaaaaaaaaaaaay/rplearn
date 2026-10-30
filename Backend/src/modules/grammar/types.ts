import { z } from "zod";
import type { PreparedJob } from "../jobs/types.js";

const text = (max: number) => z.string().trim().min(1).max(max);
export const patternSchema = z
  .object({
    steps: z
      .array(
        text(100).regex(
          /^(?:<(?:word|gerund|past-participle|comparative)>|[a-z]+(?:'[a-z]+)?(?:\|[a-z]+(?:'[a-z]+)?)*)$/,
        ),
      )
      .min(2)
      .max(8),
    maximumGaps: z.array(z.number().int().min(0).max(4)).max(7),
    highlightedSteps: z.array(z.number().int().min(0).max(7)).optional(),
  })
  .refine(
    (p) =>
      p.maximumGaps.length === p.steps.length - 1 &&
      (p.highlightedSteps?.every((i) => i < p.steps.length) ?? true) &&
      p.steps.some((s) => !s.startsWith("<")),
    "Invalid bounded grammar pattern",
  );
export const conceptSchema = z.object({
  id: text(100).regex(/^[a-z][a-z0-9.-]*$/),
  title: text(100),
  explanationZh: text(1200),
  triggers: z
    .array(text(40).regex(/^[a-z]+(?:'[a-z]+)?$/))
    .min(1)
    .max(12),
  examples: z
    .array(z.object({ en: text(300), zh: text(300) }))
    .min(1)
    .max(3),
  related: z.array(text(100)).max(12).default([]),
  patterns: z.array(patternSchema).min(1).max(4),
  supersedes: z.array(text(100)).max(12).optional(),
});
export type GrammarConcept = z.infer<typeof conceptSchema>;
export const proposalSchema = conceptSchema
  .omit({ id: true, related: true, supersedes: true })
  .extend({
    identity: text(100).regex(/^[a-z]+(?:-[a-z]+)*$/),
  });
export type GrammarProposal = z.infer<typeof proposalSchema>;
export const analysisSchema = z.object({
  summaryZh: text(500),
  points: z
    .array(
      z.object({
        title: text(100),
        quote: text(600),
        pattern: text(200),
        explanationZh: text(1000),
        learnerTipZh: text(500),
        canonicalPointId: text(100).nullable().default(null),
        proposal: z.unknown().transform((value) => {
          const candidate = proposalSchema.safeParse(value);
          return candidate.success ? candidate.data : null;
        }),
      }),
    )
    .min(1)
    .max(3),
});
export type GrammarAnalysis = z.infer<typeof analysisSchema>;
export type CatalogSnapshot = Readonly<{ revision: string; points: GrammarConcept[] }>;
export type ReviewDecision = Readonly<{
  verdict: "equivalent" | "distinct" | "uncertain";
  existingId: string | null;
  identity: string | null;
}>;
export interface GrammarRepository {
  snapshot: () => Promise<CatalogSnapshot>;
  resolution: (fingerprint: string) => Promise<string | null | undefined>;
  schedule: (
    fingerprint: string,
    proposal: GrammarProposal,
    prepare: () => PreparedJob,
  ) => Promise<void>;
  reconcile: (input: {
    snapshotRevision: string;
    fingerprint: string;
    proposal: GrammarProposal;
    decision: ReviewDecision;
  }) => Promise<string | null>;
}
