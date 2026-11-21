import { z } from "zod";
const uuid = z.uuid();
const isoDate = z.iso.datetime({ offset: true });
export const relationshipPayload = z
  .object({
    affinity: z.number().min(0).max(150),
    activityCountToday: z.number().int().min(0),
    activityDayStart: isoDate.nullable().optional(),
    bondFloor: z.number().min(0).max(120),
    care: z.number().min(0).max(1),
    familiarity: z.number().min(0).max(1),
    interactionCount: z.number().int().min(0),
    lastEvaluatedMessageID: uuid.nullable().optional(),
    lastEvaluatedMessageAt: isoDate.nullable().optional(),
    lastEvaluatedOrderIndex: z.number().int().min(-1),
    lastInteractionAt: isoDate.nullable().optional(),
    lastSubstantiveInteractionAt: isoDate.nullable().optional(),
    meaningfulInteractionCount: z.number().int().min(0),
    positiveGainToday: z.number().min(0).max(4),
    repairGainToday: z.number().min(0).max(2).optional(),
    expectedSocialQuality: z.number().min(-1).max(1).optional(),
    interactionStability: z.number().min(0).max(1).optional(),
    substantiveIntervalSampleCount: z.number().int().min(0).max(10_000).optional(),
    typicalContactIntervalDays: z.number().min(0.5).max(120).optional(),
    rapport: z.number().min(0).max(1),
    recentEvents: z
      .array(
        z
          .object({
            createdAt: isoDate,
            delta: z.number().min(-30).max(15),
            id: uuid,
            reasonZh: z.string().trim().max(160),
            source: z.enum([
              "textChat",
              "voiceChat",
              "sharedActivity",
              "story",
              "appointment",
            ]),
          })
          .strict(),
      )
      .max(24),
    respect: z.number().min(0).max(1),
    revision: z.number().int().min(0),
    settledAppointmentIDs: z.array(uuid).max(10000).optional(),
    recentEvaluatedMessageIDs: z.array(uuid).max(64).optional(),
    schemaVersion: z.union([z.literal(1), z.literal(2), z.literal(3)]),
    trust: z.number().min(0).max(1),
    unresolvedStrain: z.number().min(0).max(1),
  })
  .strict();
