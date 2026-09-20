import { z } from "zod";

const nullableText = (maximum: number) =>
  z
    .string()
    .trim()
    .min(1)
    .max(maximum)
    .nullable()
    .optional()
    .transform((value) => value ?? null);
const shortList = (maximumItems: number, maximumLength = 120) =>
  z.array(z.string().trim().min(1).max(maximumLength)).max(maximumItems);
const timeZoneIdentifier = z
  .string()
  .trim()
  .min(1)
  .max(80)
  .refine((value) => {
    try {
      new Intl.DateTimeFormat("en-US", { timeZone: value }).format();
      return true;
    } catch {
      return false;
    }
  }, "Expected an IANA time-zone identifier.");

const personaVoice = z
  .object({
    anchorLines: shortList(8, 240),
    boundaries: shortList(8, 240),
    conversationalHabits: shortList(10, 240),
    flaws: shortList(6, 160),
    values: shortList(8, 160),
  })
  .strict();

export const publicCard = z
  .object({
    age: z.number().int().min(14).max(100),
    appearance: z.string().trim().min(1).max(2_000),
    background: nullableText(4_000),
    birthday: z
      .string()
      .regex(/^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$/)
      .nullable()
      .optional()
      .transform((value) => value ?? null),
    gender: z.enum(["female", "male", "other"]),
    hobbies: shortList(12, 80).min(1),
    hometown: nullableText(160),
    languages: shortList(12, 80),
    name: z.string().trim().min(1).max(80),
    nationality: z.string().trim().min(1).max(80),
    occupation: z.string().trim().min(1).max(120),
    personaVoice,
    personality: z.string().trim().min(1).max(2_000),
    regionId: z.string().regex(/^[a-z0-9-]{2,64}$/),
    signature: nullableText(240),
    speechStyle: nullableText(2_000),
    readingVoice: z.enum(["M1", "M2", "M3", "M4", "M5", "F1", "F2", "F3", "F4", "F5"]).optional(),
    activityProfile: z
      .object({
        timeZoneIdentifier,
        rhythm: z.enum(["earlyBird", "daytime", "nightOwl", "irregular"]),
        focusDurationMinutes: z.number().int().min(4).max(12),
      })
      .strict()
      .optional(),
  })
  .strict()
  .transform(({ activityProfile, readingVoice, ...card }) => ({
    ...card,
    ...(activityProfile === undefined ? {} : { activityProfile }),
    ...(readingVoice === undefined ? {} : { readingVoice }),
  }));
