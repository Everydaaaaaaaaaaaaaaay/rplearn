import { relationshipPayload } from "../content/relationship-contract.js";
import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import { AppError } from "../../shared/errors.js";
import type { AppointmentService, AppointmentSettlementSeed } from "./contracts.js";
const uuid = z.uuid().transform((v) => v.toLowerCase());
const command = z.object({
  commandId: uuid,
  expectedRevision: z.number().int().nonnegative(),
});
const params = z.object({ id: uuid });
function parse<T>(schema: z.ZodType<T>, input: unknown): T {
  const result = schema.safeParse(input);
  if (!result.success)
    throw new AppError({
      code: "INVALID_REQUEST",
      message: "赴约请求格式不正确。",
      statusCode: 400,
    });
  return result.data;
}
type Service = AppointmentService & {
  settlementSeed(userId: string, id: string): Promise<AppointmentSettlementSeed>;
  settle(
    userId: string,
    id: string,
    input: {
      commandId: string;
      expectedCharacterVersion: number;
      relationship: Record<string, unknown>;
    },
  ): ReturnType<AppointmentService["detail"]>;
};
export function registerAppointmentRoutes(
  app: FastifyInstance,
  auth: AuthService,
  service: Service,
) {
  app.get("/v1/appointments", async (request, reply) => {
    const actor = await authenticateRequest(request, auth);
    reply.header("cache-control", "no-store");
    return service.list(actor.userId);
  });
  app.post("/v1/appointments/detect", async (request, reply) => {
    const actor = await authenticateRequest(request, auth);
    const body = parse(
      z.object({ characterId: uuid, conversationId: uuid }).strict(),
      request.body,
    );
    reply.header("cache-control", "no-store");
    return service.detect(actor.userId, body);
  });
  app.get("/v1/appointments/:id", async (request, reply) => {
    const actor = await authenticateRequest(request, auth);
    const { id } = parse(params, request.params);
    reply.header("cache-control", "no-store");
    return service.detail(actor.userId, id);
  });
  for (const kind of ["start", "choices", "cancel"] as const)
    app.post(`/v1/appointments/:id/${kind}`, async (request, reply) => {
      const actor = await authenticateRequest(request, auth);
      const { id } = parse(params, request.params);
      const body =
        kind === "choices"
          ? parse(
              command
                .extend({
                  choiceId: z.string().min(1).max(128).optional(),
                  input: z.string().min(1).max(2000).optional(),
                  finish: z.literal(true).optional(),
                })
                .strict(),
              request.body,
            )
          : parse(command.strict(), request.body);
      reply.header("cache-control", "no-store");
      return kind === "start"
        ? service.start(actor.userId, id, body)
        : kind === "cancel"
          ? service.cancel(actor.userId, id, body)
          : service.choose(actor.userId, id, body);
    });
  app.get("/v1/appointments/:id/settlement", async (request, reply) => {
    const actor = await authenticateRequest(request, auth);
    const { id } = parse(params, request.params);
    reply.header("cache-control", "no-store");
    return service.settlementSeed(actor.userId, id);
  });
  app.post("/v1/appointments/:id/settle", async (request, reply) => {
    const actor = await authenticateRequest(request, auth);
    const { id } = parse(params, request.params);
    const body = parse(
      z
        .object({
          commandId: uuid,
          expectedCharacterVersion: z.number().int().positive(),
          relationship: relationshipPayload,
        })
        .strict(),
      request.body,
    );
    reply.header("cache-control", "no-store");
    return service.settle(actor.userId, id, body);
  });
}
