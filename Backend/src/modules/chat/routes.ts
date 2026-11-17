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
  app.get("/v1/chat/followups", async (request, reply) => {
    reply.header("cache-control", "no-store");
    const identity = await authenticateRequest(request, auth);
    return chat.followups.pending(identity.userId);
  });
  app.post("/v1/chat/followups/:messageId/claim", async (request, reply) => {
    reply.header("cache-control", "no-store");
    const identity = await authenticateRequest(request, auth);
    const { messageId } = parse(z.object({ messageId: z.uuid() }), request.params);
    const { review } = parse(
      z.strictObject({
        review: z.strictObject({
          system: z.string().max(40000),
          input: z.string().max(100000),
          schema: z.record(z.string(), z.unknown()),
        }),
      }),
      request.body,
    );
    return chat.followups.claim(identity.userId, messageId, review);
  });
  app.post("/v1/chat/followups/:messageId/complete", async (request) => {
    const identity = await authenticateRequest(request, auth);
    const { messageId } = parse(z.object({ messageId: z.uuid() }), request.params);
    const { token } = parse(z.strictObject({ token: z.uuid() }), request.body);
    return chat.followups.complete(identity.userId, messageId, token);
  });
  app.post(
    "/v1/chat/conversations/:conversationId/voice-receipt",
    async (request, reply) => {
      reply.header("cache-control", "no-store");
      const identity = await authenticateRequest(request, auth);
      const { conversationId } = parse(conversationParams, request.params);
      const body = parse(
        z.strictObject({
          messageId: z.uuid(),
          text: z.string().max(40000),
          interrupted: z.boolean(),
        }),
        request.body,
      );
      return chat.voiceReceipt(
        identity.userId,
        conversationId,
        body.messageId,
        body.text,
        body.interrupted,
      );
    },
  );
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
  app.post(
    "/v1/chat/conversations/:conversationId/composer",
    async (request, reply) => {
      reply.header("cache-control", "no-store");
      const identity = await authenticateRequest(request, auth);
      const params = parse(conversationParams, request.params);
      const body = parse(
        z.strictObject({
          sessionId: z.uuid(),
          sequence: z.number().int().min(0).max(2_000_000_000),
          activity: z.enum(["edited", "blurred", "sent", "inactive"]),
          remainingMilliseconds: z.number().min(0).max(25_000),
        }),
        request.body,
      );
      const accepted = await chat.composerActivity(
        identity.userId,
        params.conversationId,
        body,
      );
      return { accepted };
    },
  );
}
