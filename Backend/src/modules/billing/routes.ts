import type { FastifyInstance, FastifyRequest } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { BillingService } from "./service.js";

const signedPayloadSchema = z.object({
  signedPayload: z.string().min(32).max(512_000),
});

const signedTransactionSchema = z.object({
  signedTransaction: z.string().min(32).max(256_000),
});

const debugEntitlementSchema = z.object({
  durationDays: z.number().int().min(1).max(365).default(30),
  tier: z.enum(["plus", "pro"]),
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

export function registerBillingRoutes(
  app: FastifyInstance,
  authService: AuthService,
  billingService: BillingService,
  options: Readonly<{
    appleBillingEnabled: boolean;
    enableDebugRoutes: boolean;
  }>,
): void {
  app.get(
    "/v1/billing/products",
    {
      schema: {
        tags: ["billing"],
      },
    },
    async () => ({
      products: await billingService.listProducts(),
      applePurchasesEnabled: options.appleBillingEnabled,
    }),
  );

  app.get(
    "/v1/billing/entitlements",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["billing"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, authService);
      return billingService.getEntitlements(identity.userId);
    },
  );

  if (options.appleBillingEnabled) {
    app.post(
      "/v1/billing/apple/transactions",
      {
        schema: {
          security: [{ bearerAuth: [] }],
          tags: ["billing"],
        },
      },
      async (request) => {
        const identity = await authenticateRequest(request, authService);
        const body = parse(signedTransactionSchema, request.body);
        return billingService.ingestAppleTransaction(
          identity.userId,
          commandId(request),
          body.signedTransaction,
        );
      },
    );

    app.post(
      "/v1/billing/apple/notifications",
      {
        schema: {
          tags: ["billing-provider"],
        },
      },
      async (request, reply) => {
        const body = parse(signedPayloadSchema, request.body);
        await billingService.ingestAppleNotification(body.signedPayload);
        return reply.status(204).send();
      },
    );
  }

  if (options.enableDebugRoutes) {
    app.post(
      "/v1/dev/billing/entitlements",
      {
        schema: {
          security: [{ bearerAuth: [] }],
          tags: ["development"],
        },
      },
      async (request) => {
        const identity = await authenticateRequest(request, authService);
        const body = parse(debugEntitlementSchema, request.body);
        return billingService.grantDebugEntitlement(
          identity.userId,
          commandId(request),
          body.tier,
          body.durationDays,
        );
      },
    );
  }
}
