import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { SyncCommand, SyncService } from "./service.js";

const difficultySchema = z.enum([
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

const purchaseCommandSchema = z.object({
  commandId: z.uuid(),
  payload: z
    .object({
      countryCode: z
        .string()
        .regex(/^[A-Za-z]{2}$/)
        .optional(),
      type: z.enum(["universal", "country"]),
    })
    .refine(
      (value) => value.type === "universal" || value.countryCode !== undefined,
      "Country tickets require a country code",
    ),
  type: z.literal("economy.purchaseTicket"),
});

const profileCommandSchema = z.object({
  commandId: z.uuid(),
  payload: z
    .object({
      difficulty: difficultySchema.optional(),
      displayName: z.string().trim().min(1).max(80).optional(),
      expectedVersion: z.number().int().positive(),
      hasCompletedOnboarding: z.boolean().optional(),
      quizGloballyEnabled: z.boolean().optional(),
    })
    .refine(
      (value) =>
        value.difficulty !== undefined ||
        value.displayName !== undefined ||
        value.hasCompletedOnboarding !== undefined ||
        value.quizGloballyEnabled !== undefined,
      "At least one profile field must be updated",
    ),
  type: z.literal("profile.update"),
});

const travelCommandSchema = z.object({
  commandId: z.uuid(),
  payload: z.object({
    targetRegionId: z.string().regex(/^[a-z0-9-]{2,64}$/),
    ticketId: z.uuid().optional(),
  }),
  type: z.literal("travel.go"),
});

const commandBatchSchema = z.object({
  commands: z
    .array(
      z.discriminatedUnion("type", [
        purchaseCommandSchema,
        profileCommandSchema,
        travelCommandSchema,
      ]),
    )
    .min(1)
    .max(50),
});

const changesQuerySchema = z.object({
  cursor: z.string().min(1).max(1024).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(100),
});

function parse<T>(schema: ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value);
  if (!result.success) {
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

export function registerSyncRoutes(
  app: FastifyInstance,
  authService: AuthService,
  syncService: SyncService,
): void {
  app.get(
    "/v1/sync/snapshot",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["sync"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      return syncService.getSnapshot(identity.userId);
    },
  );

  app.get(
    "/v1/sync/changes",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["sync"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      const query = parse(changesQuerySchema, request.query);
      return syncService.getChanges(identity.userId, query.cursor, query.limit);
    },
  );

  app.post(
    "/v1/sync/commands",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["sync"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      const body = parse(commandBatchSchema, request.body);
      return {
        results: await syncService.executeCommands(
          identity.userId,
          body.commands as readonly SyncCommand[],
        ),
      };
    },
  );
}
