import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { UnitLearningService } from "./unit-service.js";

const character = z.object({ characterId: z.uuid() });
const role = z.enum(["oliver", "ruby", "marcus", "other"]);
const message = z.object({
  characterId: z.uuid(), roleKey: role, messageId: z.uuid(),
  role: z.enum(["user", "assistant"]), characterCount: z.number().int().min(1).max(4000),
});
const start = z.object({ characterId: z.uuid(), roleKey: role, contentVersion: z.literal(2).optional() });
const answer = z.object({ attemptId: z.uuid(), questionId: z.string().min(1).max(64), answer: z.string().min(1).max(200) });
const level = z.object({ characterId: z.uuid(), roleKey: role, grade: z.number().int().min(1).max(12), acknowledge: z.literal(true) });

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value);
  if (!result.success) throw new AppError({ code: "INVALID_REQUEST", message: "Invalid learning request.", statusCode: 400 });
  return result.data;
}

export function registerUnitLearningRoutes(app: FastifyInstance, auth: AuthService, service: UnitLearningService): void {
  app.get("/v1/learning/units/characters/:characterId", async (request, reply) => {
    const identity = await authenticateRequest(request, auth);
    const { characterId } = parse(character, request.params);
    const { roleKey } = parse(z.object({ roleKey: role }), request.query);
    reply.header("cache-control", "no-store");
    return service.read(identity.userId, characterId, roleKey);
  });
  app.post("/v1/learning/units/messages", async (request, reply) => {
    const identity = await authenticateRequest(request, auth);
    const body = parse(message, request.body);
    reply.header("cache-control", "no-store");
    return service.recordMessage(identity.userId, body);
  });
  app.post("/v1/learning/units/start", async (request, reply) => {
    const identity = await authenticateRequest(request, auth);
    const body = parse(start, request.body);
    reply.header("cache-control", "no-store");
    return service.start(identity.userId, body.characterId, body.roleKey, body.contentVersion ?? 1);
  });
  app.post("/v1/learning/units/answer", async (request, reply) => {
    const identity = await authenticateRequest(request, auth);
    const body = parse(answer, request.body);
    reply.header("cache-control", "no-store");
    return service.answer(identity.userId, body.attemptId, body.questionId, body.answer);
  });
  app.post("/v1/learning/units/level", async (request, reply) => {
    const identity = await authenticateRequest(request, auth);
    const body = parse(level, request.body);
    reply.header("cache-control", "no-store");
    return service.changeGrade(identity.userId, body.characterId, body.roleKey, body.grade);
  });
}
