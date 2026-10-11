import { levelSchema } from "./content.js";
import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import { AppError } from "../../shared/errors.js";
import type { LearningService } from "./service.js";
import { answerSchema } from "./grading.js";
const paramsSchema = z.strictObject({ id: z.uuid() });
const requestSchema = z.strictObject({ requestId: z.uuid() });
const revisionSchema = requestSchema.extend({
  expectedRevision: z.number().int().min(1),
});
const historySchema = z.strictObject({
  limit: z.coerce.number().int().min(1).max(50).default(20),
  cursor: z.string().min(1).max(512).optional(),
});
function parse<T>(schema: ZodType<T>, input: unknown): T {
  const result = schema.safeParse(input);
  if (!result.success)
    throw new AppError({
      code: "INVALID_REQUEST",
      message: "学习请求格式不正确。",
      statusCode: 400,
    });
  return result.data;
}

export function registerLearningRoutes(
  app: FastifyInstance,
  auth: AuthService,
  service: LearningService,
): void {
  app.register((scope, _options, done) => {
    scope.addHook("onRequest", async (request, reply) => {
      reply.header("cache-control", "no-store");
      await authenticateRequest(request, auth);
    });
    const user = (request: { authUserId: string | null }) => {
      if (!request.authUserId) throw new Error("学习请求尚未鉴权。");
      return request.authUserId;
    };
    scope.post(
      "/v1/dev/learning/characters/:id/fill",
      { bodyLimit: 1024 },
      (request) => {
        const userId = user(request);
        const body = parse(requestSchema.extend({ cycleId: z.uuid() }), request.body);
        return service.debugFill(
          userId,
          body.requestId,
          parse(paramsSchema, request.params).id,
          body.cycleId,
        );
      },
    );
    scope.post("/v1/learning/promotions", { bodyLimit: 1024 }, (request) => {
      const body = parse(requestSchema.extend({ level: levelSchema }), request.body);
      return service.beginPromotion(user(request), body.requestId, body.level);
    });
    scope.get("/v1/learning/promotions/:id", (request) =>
      service.promotion(user(request), parse(paramsSchema, request.params).id),
    );
    scope.post(
      "/v1/learning/promotions/:id/advance",
      { bodyLimit: 1024 },
      (request) => {
        const body = parse(revisionSchema, request.body);
        return service.advancePromotion(
          user(request),
          body.requestId,
          parse(paramsSchema, request.params).id,
          body.expectedRevision,
        );
      },
    );
    scope.post(
      "/v1/learning/promotions/:id/complete",
      { bodyLimit: 1024 },
      (request) => {
        const body = parse(
          revisionSchema.extend({
            expectedProfileVersion: z.number().int().positive(),
            confirmed: z.literal(true),
          }),
          request.body,
        );
        return service.completePromotion(
          user(request),
          body.requestId,
          parse(paramsSchema, request.params).id,
          body.expectedRevision,
          body.expectedProfileVersion,
        );
      },
    );
    scope.get("/v1/learning/journey", (request) => service.journey(user(request)));
    scope.get("/v1/learning/characters/:id", (request) =>
      service.character(user(request), parse(paramsSchema, request.params).id),
    );
    scope.get("/v1/learning/characters/:id/history", (request) => {
      const query = parse(historySchema, request.query);
      return service.history(
        user(request),
        parse(paramsSchema, request.params).id,
        query.limit,
        query.cursor,
      );
    });
    scope.post(
      "/v1/learning/characters/:id/attempts",
      { bodyLimit: 1024 },
      async (request, reply) => {
        const body = parse(requestSchema, request.body);
        const result = await service.start(
          user(request),
          body.requestId,
          parse(paramsSchema, request.params).id,
        );
        if (result.status === "preparing") reply.code(202);
        return result;
      },
    );
    scope.get("/v1/learning/attempts/:id", (request) =>
      service.attempt(user(request), parse(paramsSchema, request.params).id),
    );
    scope.get("/v1/learning/attempts/:id/audio/:questionId", (request) => {
      const params = parse(
        paramsSchema.extend({
          questionId: z.string().regex(/^[a-z][a-z0-9_.-]{0,119}$/),
        }),
        request.params,
      );
      const query = parse(
        z.strictObject({
          assetId: z
            .string()
            .regex(/^audio\.[a-f0-9]{64}$/)
            .optional(),
        }),
        request.query,
      );
      return service.audio(user(request), params.id, params.questionId, query.assetId);
    });
    scope.get("/v1/learning/attempts/:id/images/:questionId/:assetId", (request) => {
      const params = parse(
        paramsSchema.extend({
          questionId: z.string().regex(/^[a-z][a-z0-9_.-]{0,119}$/),
          assetId: z.string().regex(/^image\.[a-f0-9]{64}$/),
        }),
        request.params,
      );
      return service.image(user(request), params.id, params.questionId, params.assetId);
    });
    scope.post("/v1/learning/attempts/:id/answers", { bodyLimit: 8192 }, (request) => {
      const body = parse(
        revisionSchema.extend({
          roundId: z.uuid(),
          questionId: z.string().min(1).max(120),
          answer: answerSchema,
        }),
        request.body,
      );
      const { requestId, ...input } = body;
      return service.answer(user(request), requestId, {
        ...input,
        attemptId: parse(paramsSchema, request.params).id,
      });
    });
    scope.post("/v1/learning/attempts/:id/finish", { bodyLimit: 1024 }, (request) => {
      const { requestId, ...input } = parse(
        revisionSchema.extend({ skipRemaining: z.boolean() }),
        request.body,
      );
      return service.finish(user(request), requestId, {
        ...input,
        attemptId: parse(paramsSchema, request.params).id,
      });
    });
    scope.post("/v1/learning/attempts/:id/retries", { bodyLimit: 1024 }, (request) => {
      const { requestId, ...input } = parse(revisionSchema, request.body);
      return service.retry(user(request), requestId, {
        ...input,
        attemptId: parse(paramsSchema, request.params).id,
      });
    });
    done();
  });
}
