import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateActorRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { OutingOperation, OutingService } from "./outing-types.js";

const uuid = z.uuid().transform((value) => value.toLowerCase());
const id = z.string().regex(/^[a-z0-9][a-z0-9-]{1,100}$/);
const version = z.object({
  operationId: uuid,
  expectedRevision: z.number().int().nonnegative(),
});
function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const parsed = schema.safeParse(value);
  if (!parsed.success)
    throw new AppError({
      code: "INVALID_REQUEST",
      message: "外出请求格式不正确。",
      statusCode: 400,
    });
  return parsed.data;
}

export function registerOutingRoutes(
  app: FastifyInstance,
  auth: AuthService,
  service: OutingService,
) {
  app.get("/v2/activity-world", async (request, reply) => {
    const actor = await authenticateActorRequest(request, auth);
    const query = parse(z.object({ releaseId: id.optional() }).strict(), request.query);
    reply.header("cache-control", "no-store");
    return { catalog: await service.catalog(actor.userId, query.releaseId) };
  });
  app.get("/v2/outings/active", async (request, reply) => {
    const actor = await authenticateActorRequest(request, auth);
    reply.header("cache-control", "no-store");
    return { outing: await service.active(actor.userId) };
  });
  app.get("/v2/outings/history", async (request, reply) => {
    const actor = await authenticateActorRequest(request, auth);
    const query = parse(z.object({ before: uuid.optional() }).strict(), request.query);
    reply.header("cache-control", "no-store");
    return service.history(actor.userId, query.before);
  });
  app.get("/v2/outings/:runId", async (request, reply) => {
    const actor = await authenticateActorRequest(request, auth);
    const { runId } = parse(z.object({ runId: uuid }).strict(), request.params);
    reply.header("cache-control", "no-store");
    return service.find(actor.userId, runId);
  });
  app.post("/v2/outings", async (request, reply) => {
    const actor = await authenticateActorRequest(request, auth);
    const input = parse(
      z.object({ runId: uuid, releaseId: id, placeId: id }).strict(),
      request.body,
    );
    reply.header("cache-control", "no-store");
    return service.start(actor.userId, input);
  });
  for (const [path, type] of [
    ["read", "read"],
    ["presented", "presented"],
    ["choices", "choice"],
    ["complete", "complete"],
    ["abandon", "abandon"],
  ] as const) {
    app.post(`/v2/outings/:runId/${path}`, async (request, reply) => {
      const actor = await authenticateActorRequest(request, auth);
      const { runId } = parse(z.object({ runId: uuid }).strict(), request.params);
      const body =
        type === "read"
          ? parse(
              version.extend({ beatIndex: z.number().int().nonnegative() }).strict(),
              request.body,
            )
          : type === "choice"
            ? parse(
                version
                  .extend({ choiceId: z.string().regex(/^(start|a|b):[01]$/) })
                  .strict(),
                request.body,
              )
            : parse(version.strict(), request.body);
      reply.header("cache-control", "no-store");
      return service.apply(actor.userId, runId, { ...body, type } as OutingOperation);
    });
  }
}
