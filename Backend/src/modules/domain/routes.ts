import type { FastifyInstance, FastifyRequest } from "fastify";
import { z, type ZodType } from "zod";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import { AppError } from "../../shared/errors.js";
import type { DomainService } from "./service.js";

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

const profilePatchSchema = z
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
  );

const ticketPurchaseSchema = z
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
  );

const travelSchema = z.object({
  targetRegionId: z.string().regex(/^[a-z0-9-]{2,64}$/),
  ticketId: z.uuid().optional(),
});

const grantCoinsSchema = z.object({
  amount: z.number().int().min(1).max(100_000),
});

const grantTicketSchema = ticketPurchaseSchema;

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

function commandId(request: FastifyRequest): string {
  const value = request.headers["idempotency-key"];
  const result = z.uuid().safeParse(value);
  if (!result.success) {
    throw new AppError({
      code: "IDEMPOTENCY_KEY_REQUIRED",
      message: "A UUID idempotency-key header is required.",
      statusCode: 400,
    });
  }
  return result.data;
}

export function registerDomainRoutes(
  app: FastifyInstance,
  authService: AuthService,
  domainService: DomainService,
  options: Readonly<{ enableDebugRoutes: boolean }>,
): void {
  app.get(
    "/v1/me",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["users"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      return domainService.getSnapshot(identity.userId);
    },
  );

  app.patch(
    "/v1/me",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["users"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      const patch = parse(profilePatchSchema, request.body);
      return domainService.updateProfile(identity.userId, commandId(request), {
        ...(patch.difficulty === undefined ? {} : { difficulty: patch.difficulty }),
        ...(patch.displayName === undefined ? {} : { displayName: patch.displayName }),
        expectedVersion: patch.expectedVersion,
        ...(patch.hasCompletedOnboarding === undefined
          ? {}
          : {
              hasCompletedOnboarding: patch.hasCompletedOnboarding,
            }),
        ...(patch.quizGloballyEnabled === undefined
          ? {}
          : { quizGloballyEnabled: patch.quizGloballyEnabled }),
      });
    },
  );

  app.post(
    "/v1/economy/tickets/purchase",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["economy"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      const body = parse(ticketPurchaseSchema, request.body);
      return domainService.purchaseTicket(
        identity.userId,
        commandId(request),
        body.type,
        body.countryCode,
      );
    },
  );

  app.post(
    "/v1/travel",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["travel"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      const body = parse(travelSchema, request.body);
      return domainService.travel(
        identity.userId,
        commandId(request),
        body.targetRegionId,
        body.ticketId,
      );
    },
  );

  if (options.enableDebugRoutes) {
    app.post(
      "/v1/dev/economy/coins",
      {
        schema: {
          security: [{ bearerAuth: [] }],
          tags: ["development"],
        },
      },
      async (request) => {
        const identity = await authenticateRequest(request, authService);
        const body = parse(grantCoinsSchema, request.body);
        return domainService.grantCoins(
          identity.userId,
          commandId(request),
          body.amount,
          "debug_grant",
        );
      },
    );

    app.post(
      "/v1/dev/economy/tickets",
      {
        schema: {
          security: [{ bearerAuth: [] }],
          tags: ["development"],
        },
      },
      async (request) => {
        const identity = await authenticateRequest(request, authService);
        const body = parse(grantTicketSchema, request.body);
        return domainService.grantTicket(
          identity.userId,
          commandId(request),
          body.type,
          "debug",
          body.countryCode,
        );
      },
    );
  }
}
