import { z } from "zod";

const text = z.string().trim().min(1).max(240);
const tags = z
  .array(text)
  .max(64)
  .refine((items) => new Set(items).size === items.length);
const https = z
  .url()
  .max(2048)
  .refine((url) => url.startsWith("https://"));

// Metadata is an operator's reviewed assertion, never evidence inferred from an image.
export const avatarMetadataSchema = z
  .object({
    cultures: tags,
    interestIndependent: z.boolean().default(false),
    subjects: tags,
    aesthetics: tags,
    expressions: tags,
    regions: tags,
    eras: tags,
    source: z
      .object({
        kind: z.enum(["licensed", "generated", "commissioned"]),
        pageUrl: https,
        creator: text,
        license: text,
        licenseUrl: https,
        evidence: z.string().trim().min(1).max(4000),
        attribution: z.string().trim().max(2000),
        attributionRequired: z.boolean(),
        reviewedBy: text,
        reviewedAt: z.iso.datetime(),
        commercialUse: z.literal(true),
        derivatives: z.literal(true),
        distribution: z.literal(true),
        generation: z
          .object({ model: text, prompt: z.string().min(1).max(8000) })
          .strict()
          .optional(),
      })
      .strict(),
    quality: z
      .object({
        squareCropChecked: z.literal(true),
        smallSizeChecked: z.literal(true),
        culturalAccuracyChecked: z.literal(true),
        safetyChecked: z.literal(true),
        similarityChecked: z.literal(true),
      })
      .strict(),
  })
  .strict()
  .superRefine((value, context) => {
    if (value.source.attributionRequired && value.source.attribution.length === 0) {
      context.addIssue({
        code: "custom",
        message: "Required attribution must be provided",
      });
    }
    if (value.cultures.length + value.subjects.length === 0) {
      context.addIssue({
        code: "custom",
        message: "At least one culture or subject is required",
      });
    }
    if (value.source.kind === "generated" && !value.source.generation) {
      context.addIssue({
        code: "custom",
        message: "Generated images require model and prompt provenance",
      });
    }
  });
export type AvatarMetadata = z.infer<typeof avatarMetadataSchema>;

export const avatarManifestSchema = z
  .object({
    version: z.literal(2),
    avatars: z
      .array(
        z
          .object({
            id: z.uuid(),
            familyId: z.uuid(),
            sha256: z.string().regex(/^[a-f0-9]{64}$/),
            url: https,
            enabled: z.boolean().default(true),
            reserved: z.boolean().default(false),
            metadata: avatarMetadataSchema,
          })
          .strict(),
      )
      .min(1)
      .max(10000),
  })
  .strict()
  .superRefine((value, context) => {
    for (const field of ["id", "url", "sha256"] as const) {
      if (
        new Set(value.avatars.map((avatar) => avatar[field])).size !==
        value.avatars.length
      ) {
        context.addIssue({ code: "custom", message: `Duplicate ${field} in manifest` });
      }
    }
  });
export type AvatarManifest = z.infer<typeof avatarManifestSchema>;
