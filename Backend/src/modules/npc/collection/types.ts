import { z } from "zod";
import { avatarMetadataSchema } from "../avatar-catalog.js";

export const providerSchema = z.enum([
  "commons",
  "cleveland",
  "artic",
  "openverse",
  "met",
]);
export type Provider = z.infer<typeof providerSchema>;
const key = z.string().regex(/^[a-z0-9][a-z0-9-]{0,79}$/);
export const discoveryPlanSchema = z
  .object({
    version: z.literal(1),
    topics: z
      .array(
        z
          .object({
            id: key,
            label: z.string().min(1).max(160),
            cultures: z.array(key).min(1).max(12),
            domain: key,
            target: z.number().int().min(1).max(100),
            searches: z
              .array(
                z
                  .object({
                    provider: providerSchema,
                    query: z.string().trim().min(1).max(240),
                    language: z.string().min(2).max(16),
                  })
                  .strict(),
              )
              .min(1)
              .max(8),
          })
          .strict(),
      )
      .min(1)
      .max(1000),
  })
  .strict()
  .refine(
    (value) =>
      new Set(value.topics.map((topic) => topic.id)).size === value.topics.length,
    "Topic IDs must be unique",
  );
export type DiscoveryPlan = z.infer<typeof discoveryPlanSchema>;

export type SourceImage = Readonly<{
  sourceId: string;
  provider: Provider;
  title: string;
  creator: string;
  recordURL: string;
  imageURL: string | null;
  licenseLabel: string;
  licenseURL: string | null;
  attribution: string;
  rightsScreen: "eligible-for-review" | "manual-license-review";
  rightsReason: string;
  evidence: Record<string, unknown>;
}>;
export type SearchPage = Readonly<{
  images: readonly SourceImage[];
  nextOffset: number | null;
}>;
const sourceImageSchema = z.object({
  sourceId: z.string(),
  provider: providerSchema,
  title: z.string(),
  creator: z.string(),
  recordURL: z.string(),
  imageURL: z.string().nullable(),
  licenseLabel: z.string(),
  licenseURL: z.string().nullable(),
  attribution: z.string(),
  rightsScreen: z.enum(["eligible-for-review", "manual-license-review"]),
  rightsReason: z.string(),
  evidence: z.record(z.string(), z.unknown()),
});
const candidateSchema = z.object({
  id: z.uuid(),
  source: sourceImageSchema,
  discoveredAt: z.iso.datetime(),
  topicIds: z.array(z.string()),
  file: z
    .object({
      path: z.string().regex(/^images\/[a-f0-9]{64}\.(jpg|png|webp)$/u),
      sha256: z.string().regex(/^[a-f0-9]{64}$/u),
      dhash: z.string().regex(/^[a-f0-9]{16}$/u),
      width: z.number().int().positive(),
      height: z.number().int().positive(),
      cropRetention: z.number().min(0).max(1),
      bytes: z.number().int().positive(),
    })
    .optional(),
  downloadError: z.string().optional(),
});
export type Candidate = z.infer<typeof candidateSchema>;
export const collectionStateSchema = z.object({
  version: z.literal(1),
  candidates: z.record(z.uuid(), candidateSchema),
  searches: z.record(
    z.string(),
    z.object({
      offset: z.number().int().nonnegative(),
      exhausted: z.boolean(),
      pages: z.number().int().nonnegative(),
      error: z.string().optional(),
    }),
  ),
});
export type CollectionState = z.infer<typeof collectionStateSchema>;
export type CollectionOptions = Readonly<{
  outputDirectory: string;
  maxPagesPerSearch: number;
  maxDownloads: number;
}>;

export const reviewSchema = z
  .object({
    version: z.literal(1),
    decisions: z
      .array(
        z.discriminatedUnion("decision", [
          z
            .object({
              candidateId: z.uuid(),
              sha256: z.string().regex(/^[a-f0-9]{64}$/),
              decision: z.literal("approve"),
              familyId: z.uuid(),
              metadata: avatarMetadataSchema,
              originalSourceCheck: z
                .object({
                  pageUrl: z.url(),
                  licenseUrl: z.url(),
                  evidence: z.string().trim().min(1).max(2000),
                  checkedAt: z.iso.datetime(),
                })
                .strict()
                .optional(),
              distinctFrom: z.array(z.uuid()).max(1000).default([]),
            })
            .strict(),
          z
            .object({
              candidateId: z.uuid(),
              decision: z.literal("reject"),
              reason: z.string().min(1).max(2000),
            })
            .strict(),
        ]),
      )
      .max(10000),
  })
  .strict()
  .refine(
    (value) =>
      new Set(value.decisions.map((decision) => decision.candidateId)).size ===
      value.decisions.length,
    "One decision per candidate",
  );
export type Review = z.infer<typeof reviewSchema>;
