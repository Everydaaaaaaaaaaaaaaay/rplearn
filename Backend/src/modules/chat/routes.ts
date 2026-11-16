import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { ChatService } from "./service.js";

function parse<T>(schema: z.ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value);
  if (!result.success)
    throw new AppError({
      code: "INVALID_REQUEST",
      message: "聊天请求格式无效。",
      statusCode: 400,
    });
  return result.data;
}
const characterParams = z.object({ characterId: z.uuid() });
const conversationParams = z.object({ conversationId: z.uuid() });
export function registerChatRoutes(
  app: FastifyInstance,
  auth: AuthService,
  chat: ChatService,
): void {
  app.post("/v1/chat/characters/:characterId/open", async (request, reply) => {
    reply.header("cache-control", "no-store");
    const identity = await authenticateRequest(request, auth);
    const params = parse(characterParams, request.params);
    parse(z.strictObject({ protocolVersion: z.literal(1) }), request.body);
    return chat.open(identity.userId, params.characterId);
  });
  app.get("/v1/chat/conversations/:conversationId", async (request, reply) => {
    reply.header("cache-control", "no-store");
    const identity = await authenticateRequest(request, auth);
    const params = parse(conversationParams, request.params);
    const query = parse(
      z.object({
        inputMessageId: z.uuid().optional(),
        afterSequence: z.coerce.number().int().min(0).max(2_000_000_000).default(0),
      }),
      request.query,
    );
    return chat.state(
      identity.userId,
      params.conversationId,
      query.afterSequence,
      query.inputMessageId,
    );
  });
  app.post("/v1/chat/conversations/:conversationId/retry", async (request, reply) => {
    reply.header("cache-control", "no-store");
    const identity = await authenticateRequest(request, auth);
    const params = parse(conversationParams, request.params);
    const body = parse(z.strictObject({ commandId: z.uuid() }), request.body);
    return chat.retry(identity.userId, params.conversationId, body.commandId);
  });
}
