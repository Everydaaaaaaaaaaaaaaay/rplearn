import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import type { AdminAuthenticator } from "../admin/http.js";
import type { DiagnosticsService } from "./diagnostics-service.js";

const querySchema = z
  .object({
    hours: z.coerce
      .number()
      .refine((value) => [1, 6, 24, 72].includes(value))
      .default(24),
    service: z.enum(["all", "api", "worker"]).default("all"),
    level: z.enum(["all", "info", "warn", "error"]).default("all"),
    requestId: z
      .string()
      .regex(/^[a-zA-Z0-9._:/-]{0,200}$/)
      .default(""),
    errorCode: z
      .string()
      .regex(/^[a-zA-Z0-9._-]{0,100}$/)
      .default(""),
    offset: z.coerce.number().int().min(0).max(20_000).default(0),
    limit: z.coerce.number().int().min(1).max(100).default(50),
  })
  .strict();

export function registerDiagnosticsRoutes(
  app: FastifyInstance,
  authenticate: AdminAuthenticator,
  service: DiagnosticsService,
): void {
  app.get(
    "/internal/admin/diagnostics",
    { schema: { hide: true } },
    async (request, reply) => {
      authenticate(request);
      reply.header("cache-control", "no-store");
      const query = querySchema.safeParse(request.query);
      if (!query.success)
        throw new AppError({
          code: "INVALID_REQUEST",
          message: "日志筛选参数无效。",
          statusCode: 400,
        });
      return service.report(query.data);
    },
  );
}
