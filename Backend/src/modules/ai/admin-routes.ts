import type { FastifyInstance, FastifyRequest } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import type { AdminAuthenticator } from "../admin/http.js";
import { aiRouteSettingsSchema } from "./config.js";
import type { AiConfigService } from "./config-service.js";
import type { AiCatalogService } from "./catalog-service.js";
import type { AiAnalyticsRepository } from "./analytics-repository.js";

const taskParamsSchema = z.object({
  task: z.string().regex(/^[a-z][a-z0-9_]{1,63}$/),
});

const updateSchema = z
  .object({
    changeReason: z.string().trim().min(8).max(500),
    expectedVersion: z.number().int().min(1),
    settings: aiRouteSettingsSchema,
  })
  .strict();

const rollbackSchema = z
  .object({
    changeReason: z.string().trim().min(8).max(500),
    expectedVersion: z.number().int().min(1),
    targetVersion: z.number().int().min(1),
  })
  .strict();

const historyQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(20),
});
const analyticsQuerySchema = z.object({
  days: z.coerce
    .number()
    .int()
    .refine((value) => [1, 7, 30, 90].includes(value))
    .default(7),
  userId: z.uuid().optional(),
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
  const result = z.uuid().safeParse(request.headers["idempotency-key"]);
  if (!result.success) {
    throw new AppError({
      code: "IDEMPOTENCY_KEY_REQUIRED",
      message: "A UUID idempotency-key header is required.",
      statusCode: 400,
    });
  }
  return result.data;
}

export function registerAiAdminRoutes(
  app: FastifyInstance,
  authenticate: AdminAuthenticator,
  service: AiConfigService,
  options: Readonly<{
    analytics?: AiAnalyticsRepository;
    catalog?: AiCatalogService;
  }> = {},
): void {
  app.get("/internal/admin/ai/routes", { schema: { hide: true } }, async (request) => {
    authenticate(request);
    return {
      allowedModels: service.allowedModels,
      providerStatus: service.providerStatus,
      routes: await service.listRoutes(),
    };
  });

  app.get("/internal/admin/ai/models", { schema: { hide: true } }, async (request) => {
    authenticate(request);
    if (options.catalog === undefined) return { models: [] };
    return {
      models: await options.catalog.listOpenRouter(),
      provider: "openrouter",
      providerStatus: service.providerStatus.openrouter,
    };
  });

  app.post(
    "/internal/admin/ai/models/openrouter/refresh",
    { schema: { hide: true } },
    async (request) => {
      authenticate(request);
      if (options.catalog === undefined) {
        throw new AppError({
          code: "AI_PROVIDER_NOT_CONFIGURED",
          message: "The OpenRouter catalog is unavailable.",
          statusCode: 503,
        });
      }
      return { models: await options.catalog.refreshOpenRouter() };
    },
  );

  app.get(
    "/internal/admin/ai/analytics",
    { schema: { hide: true } },
    async (request) => {
      authenticate(request);
      if (options.analytics === undefined) {
        throw new AppError({
          code: "AI_ANALYTICS_UNAVAILABLE",
          message: "AI analytics is unavailable.",
          statusCode: 503,
        });
      }
      const query = parse(analyticsQuerySchema, request.query);
      return options.analytics.report(query.days, query.userId ?? null);
    },
  );

  app.get(
    "/internal/admin/ai/routes/:task/revisions",
    { schema: { hide: true } },
    async (request) => {
      authenticate(request);
      const params = parse(taskParamsSchema, request.params);
      const query = parse(historyQuerySchema, request.query);
      return {
        revisions: await service.revisions(params.task, query.limit),
      };
    },
  );

  app.put(
    "/internal/admin/ai/routes/:task",
    { schema: { hide: true } },
    async (request) => {
      const operatorKeyId = authenticate(request);
      const params = parse(taskParamsSchema, request.params);
      const body = parse(updateSchema, request.body);
      return service.update(params.task, body.settings, {
        changeReason: body.changeReason,
        commandId: commandId(request),
        expectedVersion: body.expectedVersion,
        operatorKeyId,
      });
    },
  );

  app.post(
    "/internal/admin/ai/routes/:task/rollback",
    { schema: { hide: true } },
    async (request) => {
      const operatorKeyId = authenticate(request);
      const params = parse(taskParamsSchema, request.params);
      const body = parse(rollbackSchema, request.body);
      return service.rollback(params.task, body.targetVersion, {
        changeReason: body.changeReason,
        commandId: commandId(request),
        expectedVersion: body.expectedVersion,
        operatorKeyId,
      });
    },
  );
}
