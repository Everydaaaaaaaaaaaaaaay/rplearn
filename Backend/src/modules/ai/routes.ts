import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateActorRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { AiService } from "./service.js";
import type { AiProviderStreamEvent } from "./types.js";
import { writeSseEvent } from "./sse-writer.js";

const aiRequestSchema = z.object({
  operationId: z.uuid().optional(),
  parentOperationId: z.uuid().optional(),
  voiceLeaseId: z.uuid().optional(),
  maxOutputTokens: z.number().int().min(1).max(16_384).optional(),
  messages: z
    .array(
      z.object({
        content: z.string().min(1).max(200_000),
        role: z.enum(["assistant", "system", "user"]),
      }),
    )
    .min(1)
    .max(100),
  responseFormat: z.enum(["text", "json_object"]).default("text"),
  task: z.string().regex(/^[a-z][a-z0-9_]{1,63}$/),
});
const guestDeviceIdSchema = z
  .string()
  .trim()
  .min(8)
  .max(128)
  .regex(/^[a-zA-Z0-9._:-]+$/);

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

function streamError(error: unknown): Readonly<{
  code: string;
  retryable: boolean;
}> {
  if (error instanceof AppError) {
    return {
      code: error.code,
      retryable: error.statusCode >= 500,
    };
  }
  return {
    code: "AI_STREAM_FAILED",
    retryable: true,
  };
}

function eventData(event: AiProviderStreamEvent): unknown {
  switch (event.type) {
    case "delta":
      return { text: event.text };
    case "done":
      return {};
    case "metadata":
      return {
        model: event.model,
        providerRequestId: event.providerRequestId,
      };
    case "usage":
      return event.usage;
  }
}

export function registerAiRoutes(
  app: FastifyInstance,
  authService: AuthService,
  aiService: AiService,
  options: Readonly<{ guestAccessEnabled: boolean }> = {
    guestAccessEnabled: false,
  },
): void {
  const userIdFor = async (request: Parameters<typeof authenticateActorRequest>[0]) => {
    if (request.headers.authorization !== undefined) {
      return (await authenticateActorRequest(request, authService)).userId;
    }
    if (!options.guestAccessEnabled) {
      return (await authenticateActorRequest(request, authService)).userId;
    }
    const guestDeviceId = parse(
      guestDeviceIdSchema,
      request.headers["x-lingotrip-guest-id"],
    );
    const userId = await aiService.resolveGuestUser(guestDeviceId);
    request.authUserId = userId;
    return userId;
  };

  app.post(
    "/v1/ai/completions",
    {
      schema: {
        security: [{ bearerAuth: [] }, {}],
        tags: ["ai"],
      },
    },
    async (request) => {
      const userId = await userIdFor(request);
      const body = parse(aiRequestSchema, request.body);
      return aiService.complete(userId, {
        ...(body.maxOutputTokens === undefined
          ? {}
          : { maxOutputTokens: body.maxOutputTokens }),
        ...(body.operationId === undefined ? {} : { operationId: body.operationId }),
        ...(body.voiceLeaseId === undefined ? {} : { voiceLeaseId: body.voiceLeaseId }),
        ...(body.parentOperationId === undefined
          ? {}
          : { parentOperationId: body.parentOperationId }),
        messages: body.messages,
        responseFormat: body.responseFormat,
        task: body.task,
      });
    },
  );

  app.post(
    "/v1/ai/stream",
    {
      schema: {
        security: [{ bearerAuth: [] }, {}],
        tags: ["ai"],
      },
    },
    async (request, reply) => {
      const userId = await userIdFor(request);
      const body = parse(aiRequestSchema, request.body);
      const cancellation = new AbortController();
      request.raw.once("aborted", () => {
        cancellation.abort();
      });
      reply.raw.once("close", () => {
        if (!reply.raw.writableEnded) {
          cancellation.abort();
        }
      });
      const stream = await aiService.stream(userId, {
        ...(body.maxOutputTokens === undefined
          ? {}
          : { maxOutputTokens: body.maxOutputTokens }),
        ...(body.operationId === undefined ? {} : { operationId: body.operationId }),
        ...(body.voiceLeaseId === undefined ? {} : { voiceLeaseId: body.voiceLeaseId }),
        ...(body.parentOperationId === undefined
          ? {}
          : { parentOperationId: body.parentOperationId }),
        messages: body.messages,
        responseFormat: body.responseFormat,
        signal: cancellation.signal,
        task: body.task,
      });

      reply.hijack();
      reply.raw.statusCode = 200;
      reply.raw.setHeader("cache-control", "no-cache, no-transform");
      reply.raw.setHeader("content-type", "text/event-stream; charset=utf-8");
      reply.raw.setHeader("x-accel-buffering", "no");
      reply.raw.setHeader("x-ai-request-id", stream.requestId);
      reply.raw.flushHeaders();

      let clientWritable = !reply.raw.destroyed;
      const write = async (event: string, data: unknown): Promise<void> => {
        if (!clientWritable) return;
        clientWritable = await writeSseEvent(reply.raw, event, data);
      };

      try {
        for await (const event of stream.events) {
          await write(event.type, eventData(event));
        }
      } catch (error) {
        if (!reply.raw.destroyed) {
          await write("error", streamError(error));
        }
      } finally {
        if (!reply.raw.destroyed) {
          reply.raw.end();
        }
      }
      return reply;
    },
  );
}
