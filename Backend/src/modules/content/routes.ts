import { learningMessageOriginSchema } from "../learning/chat-contract.js";
import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { ContentService } from "./service.js";
import type { ContentCommand } from "./types.js";

const uuid = z.uuid();
const isoDate = z.iso.datetime({ offset: true });
const nullableText = (maximum: number) => z.string().max(maximum).nullable().optional();
const schemaVersion = z.literal(1);
const difficulty = z.enum([
  "kindergarten",
  "primary1",
  "primary2",
  "primary3",
  "primary4",
  "primary5",
  "primary6",
  "junior1",
  "junior2",
  "junior3",
  "senior1",
  "senior2",
  "senior3",
  "undergraduate",
  "postgraduate",
  "advanced",
]);

const relationshipPayload = z
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
            source: z.enum(["textChat", "voiceChat", "sharedActivity", "story"]),
          })
          .strict(),
      )
      .max(24),
    respect: z.number().min(0).max(1),
    revision: z.number().int().min(0),
    recentEvaluatedMessageIDs: z.array(uuid).max(64).optional(),
    schemaVersion: z.union([z.literal(1), z.literal(2), z.literal(3)]),
    trust: z.number().min(0).max(1),
    unresolvedStrain: z.number().min(0).max(1),
  })
  .strict();

const personaVoicePayload = z
  .object({
    anchorLines: z.array(z.string().trim().min(1).max(240)).max(8),
    boundaries: z.array(z.string().trim().min(1).max(240)).max(8),
    conversationalHabits: z.array(z.string().trim().min(1).max(240)).max(10),
    flaws: z.array(z.string().trim().min(1).max(160)).max(6),
    values: z.array(z.string().trim().min(1).max(160)).max(8),
  })
  .strict();

const activityProfilePayload = z
  .object({
    focusDurationMinutes: z.number().int().min(4).max(12),
    rhythm: z.enum(["earlyBird", "daytime", "nightOwl", "irregular"]),
    timeZoneIdentifier: z
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
      }, "Expected an IANA time-zone identifier."),
  })
  .strict();

const growthPayload = z
  .object({
    arcs: z
      .array(
        z
          .object({
            createdAt: isoDate,
            direction: z.enum(["increase", "decrease"]),
            evidenceMessageIDs: z.array(uuid).max(64),
            id: uuid,
            progress: z.number().min(0).max(1),
            reasonZh: z.string().trim().min(1).max(240),
            stage: z.enum([
              "considering",
              "experimenting",
              "integrating",
              "established",
            ]),
            trait: z.enum([
              "impulsivity",
              "patience",
              "assertiveness",
              "openness",
              "selfConfidence",
              "emotionalExpression",
              "flexibility",
              "responsibility",
            ]),
            updatedAt: isoDate,
          })
          .strict(),
      )
      .max(16),
    revision: z.number().int().min(0),
    schemaVersion: z.union([z.literal(1), z.literal(2)]),
    isPaused: z.boolean().optional(),
  })
  .strict();

const characterPayload = z
  .object({
    card: z
      .object({
        age: z.number().int().min(13).max(120),
        appearance: z.string().trim().min(1).max(2_000),
        avatarAssetName: nullableText(256),
        avatarId: nullableText(128),
        avatarRemoteUrl: z.url().max(2_048).nullable().optional(),
        background: nullableText(4_000),
        birthday: nullableText(32),
        gender: z.enum(["male", "female", "other"]),
        hobbies: z.array(z.string().trim().min(1).max(80)).max(24),
        hometown: nullableText(160),
        languages: z.array(z.string().trim().min(1).max(80)).max(12).optional(),
        name: z.string().trim().min(1).max(80),
        nationality: z.string().trim().min(1).max(80),
        occupation: z.string().trim().min(1).max(120),
        personality: z.string().trim().min(1).max(2_000),
        readingVoice: z
          .enum(["M1", "M2", "M3", "M4", "M5", "F1", "F2", "F3", "F4", "F5"])
          .optional(),
        personaVoice: personaVoicePayload.optional(),
        activityProfile: activityProfilePayload.optional(),
        regionId: z.string().regex(/^[a-z0-9-]{2,64}$/),
        signature: nullableText(240),
        speechStyle: nullableText(2_000),
      })
      .strict(),
    difficulty,
    contactStatus: z.enum(["candidate", "friend", "removed"]).optional(),
    growth: growthPayload.optional(),
    isFriend: z.boolean(),
    isFavorite: z.boolean().optional(),
    isMainCharacter: z.boolean(),
    metAt: isoDate,
    mutedUntil: isoDate.nullable().optional(),
    privateNote: nullableText(2_000),
    proactiveMessagesEnabled: z.boolean().optional(),
    publicIdentityRegistered: z.boolean().optional(),
    remarkName: nullableText(80),
    relationship: relationshipPayload.optional(),
    schemaVersion: z.union([z.literal(1), z.literal(2)]),
    travelerId: z
      .string()
      .regex(/^[0-9]{11}$/)
      .nullable()
      .optional(),
  })
  .strict();

const conversationPayload = z
  .object({
    createdAt: isoDate,
    isArchived: z.boolean(),
    isEncounterSession: z.boolean(),
    isPinned: z.boolean().optional(),
    lastMessageAt: isoDate,
    lastReadAt: isoDate.nullable().optional(),
    lastSummarizedMessageIndex: z.number().int().min(0),
    schemaVersion: z.union([z.literal(1), z.literal(2)]),
    turnCount: z.number().int().min(0),
  })
  .strict();

const messagePayload = z
  .object({
    learningOrigin: learningMessageOriginSchema.nullable().optional(),
    audioAssetId: uuid.nullable().optional(),
    audioDuration: z.number().min(0).max(3_600).nullable().optional(),
    coachReviewJson: nullableText(65_536),
    createdAt: isoDate,
    isInterrupted: z.boolean(),
    keywordRangesJson: nullableText(65_536),
    kind: z.enum(["text", "voice", "storyLine"]),
    orderIndex: z.number().int().min(0),
    role: z.enum(["user", "assistant", "coach"]),
    schemaVersion,
    speechReviewJson: nullableText(65_536),
    text: z.string().max(40_000),
    tokenEstimate: z.number().int().min(0).max(1_000_000),
    translationZh: nullableText(40_000),
  })
  .strict()
  .superRefine((value, context) => {
    if (value.audioAssetId !== null && value.audioAssetId !== undefined) {
      if (value.kind !== "voice") {
        context.addIssue({
          code: "custom",
          message: "Only voice messages can reference an audio asset.",
          path: ["audioAssetId"],
        });
      }
      if (value.audioDuration === null || value.audioDuration === undefined) {
        context.addIssue({
          code: "custom",
          message: "An uploaded voice message requires its audio duration.",
          path: ["audioDuration"],
        });
      }
    }
  });

const favoritePayload = z
  .object({
    characterName: z.string().trim().max(80),
    createdAt: isoDate,
    schemaVersion,
    sentence: z.string().trim().min(1).max(10_000),
    sourceMessageId: uuid.nullable().optional(),
    translationZh: nullableText(10_000),
  })
  .strict();

const memoryPayload = z
  .object({
    content: z.string().trim().min(1).max(4_000),
    createdAt: isoDate,
    importance: z.number().int().min(1).max(5),
    schemaVersion: z.union([z.literal(1), z.literal(2)]),
    source: z.enum(["chat", "story", "activity"]).optional(),
    sourceUpToIndex: z.number().int().min(0),
    tier: z.enum(["short", "mid", "long"]),
  })
  .strict();

const storyProgressPayload = z
  .object({
    completedAt: isoDate.nullable().optional(),
    currentNodeId: z.string().max(128).nullable().optional(),
    flags: z.record(z.string().min(1).max(64), z.boolean()),
    schemaVersion,
  })
  .strict()
  .refine((value) => Object.keys(value.flags).length <= 200, "Too many story flags");

const commandBase = {
  commandId: uuid,
  expectedVersion: z.number().int().min(0),
  operation: z.literal("upsert"),
};

const upsertCommandSchema = z.discriminatedUnion("resourceType", [
  z.object({
    ...commandBase,
    parentId: z.null().optional(),
    payload: characterPayload,
    resourceId: uuid,
    resourceType: z.literal("character"),
  }),
  z.object({
    ...commandBase,
    parentId: uuid,
    payload: conversationPayload,
    resourceId: uuid,
    resourceType: z.literal("conversation"),
  }),
  z.object({
    ...commandBase,
    parentId: z.null().optional(),
    payload: favoritePayload,
    resourceId: uuid,
    resourceType: z.literal("favorite"),
  }),
  z.object({
    ...commandBase,
    parentId: uuid,
    payload: memoryPayload,
    resourceId: uuid,
    resourceType: z.literal("memory"),
  }),
  z.object({
    ...commandBase,
    parentId: uuid,
    payload: messagePayload,
    resourceId: uuid,
    resourceType: z.literal("message"),
  }),
  z.object({
    ...commandBase,
    parentId: z.null().optional(),
    payload: storyProgressPayload,
    resourceId: z.string().regex(/^[a-z0-9_-]{1,128}$/),
    resourceType: z.literal("story_progress"),
  }),
]);

const resourceType = z.enum([
  "character",
  "conversation",
  "favorite",
  "memory",
  "message",
  "story_progress",
]);

const deleteCommandSchema = z
  .object({
    commandId: uuid,
    expectedVersion: z.number().int().positive(),
    operation: z.literal("delete"),
    resourceId: z.string().min(1).max(128),
    resourceType,
  })
  .superRefine((value, context) => {
    const valid =
      value.resourceType === "story_progress"
        ? /^[a-z0-9_-]{1,128}$/.test(value.resourceId)
        : uuid.safeParse(value.resourceId).success;
    if (!valid) {
      context.addIssue({
        code: "custom",
        message: "The resource ID is invalid for this resource type.",
        path: ["resourceId"],
      });
    }
  });

const commandBatchSchema = z.object({
  commands: z
    .array(
      z.discriminatedUnion("operation", [upsertCommandSchema, deleteCommandSchema]),
    )
    .min(1)
    .max(100),
});

const pageQuerySchema = z.object({
  cursor: z.string().min(1).max(2_048).optional(),
  limit: z.coerce.number().int().min(1).max(500).default(200),
});

function parse<T>(
  schema: ZodType<T>,
  value: unknown,
  onInvalid?: (issues: z.ZodError["issues"]) => void,
): T {
  const result = schema.safeParse(value);
  if (!result.success) {
    onInvalid?.(result.error.issues);
    throw new AppError({
      code: "INVALID_REQUEST",
      details: result.error.issues.map((issue) => ({
        code: issue.code,
        message: issue.message,
        path: issue.path,
      })),
      message: "The request is invalid.",
      statusCode: 400,
    });
  }
  return result.data;
}

export function registerContentRoutes(
  app: FastifyInstance,
  authService: AuthService,
  contentService: ContentService,
): void {
  app.get(
    "/v1/content/records",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["content"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      const query = parse(pageQuerySchema, request.query);
      return contentService.getPage(identity.userId, query.cursor, query.limit);
    },
  );

  app.post(
    "/v1/content/commands",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["content"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      const body = parse(commandBatchSchema, request.body, (issues) => {
        // 只记录校验位置和类型，不记录正文、字段值或任意剧情标记名。
        request.log.warn(
          {
            event: "content.command.validation_failed",
            issues: issues.slice(0, 20).map((issue) => ({
              code: issue.code,
              path: issue.path.map((part, index, path) =>
                path.includes("flags") && index > path.indexOf("flags")
                  ? "<flag>"
                  : part,
              ),
              ...(issue.code === "unrecognized_keys"
                ? {
                    knownLegacyKeys: issue.keys.filter((key) =>
                      [
                        "quizOptOut",
                        "quizJson",
                        "quizChosenIndex",
                        "quizGloballyEnabled",
                      ].includes(key),
                    ),
                  }
                : {}),
            })),
          },
          "内容同步校验失败",
        );
      });
      return {
        results: await contentService.executeCommands(
          identity.userId,
          body.commands.map((command) => ({
            ...command,
            ...(command.operation === "upsert"
              ? { parentId: command.parentId ?? null }
              : {}),
          })) as readonly ContentCommand[],
        ),
      };
    },
  );
}
