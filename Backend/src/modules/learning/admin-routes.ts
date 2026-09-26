import type { FastifyInstance } from "fastify";
import { z } from "zod";
import type { AdminAuthenticator } from "../admin/http.js";
import { AppError } from "../../shared/errors.js";
import type { LearningAdminService } from "./admin-service.js";
import { levelSchema, unitSchema } from "./content.js";
const filterSchema = z.strictObject({
  role: z
    .string()
    .regex(/^[a-z][a-z0-9_.-]{0,119}$/)
    .optional(),
  level: levelSchema.optional(),
  status: z.enum(["pending", "running", "review", "failed", "published"]).optional(),
  limit: z.coerce.number().int().min(1).max(50).default(30),
  offset: z.coerce.number().int().min(0).max(100000).default(0),
});
const reviewSchema = z.strictObject({
  candidateHash: z.string().regex(/^[a-f0-9]{64}$/),
  notes: z.string().trim().min(30).max(1000),
  confirmed: z.literal(true),
});
function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value);
  if (!result.success)
    throw new AppError({
      code: "INVALID_REQUEST",
      message: "请检查必填内容、审核说明和题目配置。",
      statusCode: 400,
      details: result.error.issues.map((i) => ({ path: i.path, message: i.message })),
    });
  return result.data;
}
export function registerLearningAdminRoutes(
  app: FastifyInstance,
  authenticate: AdminAuthenticator,
  service: LearningAdminService,
) {
  app.register((scope, _options, done) => {
    scope.addHook("onRequest", (request, reply, done) => {
      reply.header("cache-control", "no-store");
      authenticate(request);
      done();
    });
    scope.get("/internal/admin/learning/units", { schema: { hide: true } }, (request) =>
      service.units(parse(filterSchema, request.query)),
    );
    scope.get(
      "/internal/admin/learning/units/:id",
      { schema: { hide: true } },
      (request) => {
        const p = parse(
          z.object({ id: z.string().regex(/^[a-z][a-z0-9_.-]{0,119}$/) }),
          request.params,
        );
        const q = parse(
          z.object({ version: z.coerce.number().int().positive().optional() }),
          request.query,
        );
        return service.unit(p.id, q.version);
      },
    );
    scope.get("/internal/admin/learning/jobs", { schema: { hide: true } }, (request) =>
      service.jobs(parse(filterSchema, request.query)),
    );
    const id = (value: unknown) => parse(z.object({ id: z.uuid() }), value).id;
    scope.get(
      "/internal/admin/learning/jobs/:id",
      { schema: { hide: true } },
      (request) => service.job(id(request.params)),
    );
    scope.post(
      "/internal/admin/learning/jobs/:id/revisions",
      { schema: { hide: true }, bodyLimit: 262144 },
      (request) =>
        service.revise(
          id(request.params),
          parse(
            z.strictObject({
              requestId: z.uuid(),
              candidateHash: z.string().regex(/^[a-f0-9]{64}$/),
              notes: z.string().trim().min(30).max(1000),
              unit: unitSchema,
            }),
            request.body,
          ),
          request.operatorKeyId ?? "未知管理员",
        ),
    );
    scope.post(
      "/internal/admin/learning/jobs/:id/publish",
      { schema: { hide: true }, bodyLimit: 8192 },
      (request) => {
        const body = parse(reviewSchema, request.body);
        return service.publish(
          id(request.params),
          body.candidateHash,
          body.notes,
          request.operatorKeyId ?? "未知管理员",
        );
      },
    );
    scope.post(
      "/internal/admin/learning/jobs/:id/reject",
      { schema: { hide: true }, bodyLimit: 8192 },
      (request) => {
        const body = parse(reviewSchema, request.body);
        return service.reject(
          id(request.params),
          body.candidateHash,
          body.notes,
          request.operatorKeyId ?? "未知管理员",
        );
      },
    );
    done();
  });
}
