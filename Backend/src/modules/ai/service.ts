import { createHash, createHmac, randomUUID } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import type { RedisResource } from "../../infrastructure/redis/client.js";
import { AppError } from "../../shared/errors.js";
import { createAccessService } from "../access/service.js";
import type { BillingService } from "../billing/service.js";
import type { DeepSeekClient } from "./deepseek/client.js";
import { validateRuntimeRoute } from "./config.js";
import { AiRepository } from "./repository.js";
import type {
  AiCompletion,
  AiMessage,
  AiProviderRequest,
  AiProviderStreamEvent,
  AiResponseFormat,
  AiUsage,
} from "./types.js";

export type AiRequestInput = Readonly<{
  operationId?: string;
  parentOperationId?: string;
  voiceLeaseId?: string;
  maxOutputTokens?: number;
  messages: readonly AiMessage[];
  responseFormat: AiResponseFormat;
  signal?: AbortSignal;
  task: string;
}>;

export type AiService = Readonly<{
  complete: (
    userId: string,
    input: AiRequestInput,
  ) => Promise<
    Readonly<{
      content: string;
      model: string;
      requestId: string;
      usage: AiUsage;
    }>
  >;
  stream: (
    userId: string,
    input: AiRequestInput,
  ) => Promise<
    Readonly<{
      events: AsyncIterable<AiProviderStreamEvent>;
      requestId: string;
    }>
  >;
  resolveGuestUser: (deviceId: string) => Promise<string>;
  routeIdentity: (
    task: string,
  ) => Promise<Readonly<{ configVersion: number; model: string }>>;
}>;

function errorIdentity(error: unknown): Readonly<{
  cancelled: boolean;
  code: string;
}> {
  if (error instanceof AppError) {
    return {
      cancelled: error.code === "AI_REQUEST_CANCELLED",
      code: error.code,
    };
  }
  return {
    cancelled: false,
    code: "AI_INTERNAL_FAILURE",
  };
}

function validateInput(
  input: AiRequestInput,
  route: Awaited<ReturnType<AiRepository["route"]>>,
): Readonly<{ inputCharacters: number; maxOutputTokens: number }> {
  if (input.messages.length > route.maxMessages) {
    throw new AppError({
      code: "AI_MESSAGE_LIMIT_EXCEEDED",
      details: { limit: route.maxMessages },
      message: "The AI request contains too many messages.",
      statusCode: 413,
    });
  }
  const inputCharacters = input.messages.reduce(
    (total, message) => total + message.content.length,
    0,
  );
  if (inputCharacters > route.maxInputCharacters) {
    throw new AppError({
      code: "AI_INPUT_LIMIT_EXCEEDED",
      details: { limit: route.maxInputCharacters },
      message: "The AI request is too large.",
      statusCode: 413,
    });
  }
  if (input.responseFormat === "json_object" && !route.allowJsonResponse) {
    throw new AppError({
      code: "AI_RESPONSE_FORMAT_NOT_ALLOWED",
      message: "This AI task does not support JSON responses.",
      statusCode: 400,
    });
  }
  return {
    inputCharacters,
    maxOutputTokens: Math.min(
      input.maxOutputTokens ?? route.maxOutputTokens,
      route.maxOutputTokens,
    ),
  };
}

export function createAiService(
  config: RuntimeConfig,
  database: DatabaseResource,
  redis: RedisResource,
  _billingService: BillingService,
  deepSeek: DeepSeekClient,
): AiService {
  const repository = new AiRepository(database);
  const access = createAccessService(database);
  const userReference = (userId: string): string =>
    createHmac("sha256", config.authTokenHashPepper)
      .update(`ai-user:${userId}`)
      .digest("hex");
  const guestReference = (deviceId: string): string =>
    createHmac("sha256", config.authTokenHashPepper)
      .update(`ai-guest-device:${deviceId}`)
      .digest("hex");
  const guestUserId = (reference: string): string => {
    const hex = reference.slice(0, 32).split("");
    hex[12] = "5";
    hex[16] = ((Number.parseInt(hex[16] ?? "0", 16) & 0x3) | 0x8).toString(16);
    const value = hex.join("");
    return [
      value.slice(0, 8),
      value.slice(8, 12),
      value.slice(12, 16),
      value.slice(16, 20),
      value.slice(20),
    ].join("-");
  };

  const prepare = async (
    userId: string,
    input: AiRequestInput,
  ): Promise<
    Readonly<{
      operationId: string;
      replay: AiCompletion | null;
      providerRequest: AiProviderRequest;
      requestId: string;
      startedAt: number;
    }>
  > => {
    const route = validateRuntimeRoute(
      await repository.route(input.task),
      config.aiDeepSeekAllowedModels,
    );
    if (route.provider !== "deepseek" || !deepSeek.configured) {
      throw new AppError({
        code: "AI_PROVIDER_NOT_CONFIGURED",
        message: "The AI provider for this task is not configured.",
        statusCode: 503,
      });
    }
    const limits = validateInput(input, route);
    const minuteCount = await redis.consumeFixedWindow(
      `ai:minute:${userReference(userId)}`,
      60,
    );
    if (minuteCount > config.aiUserMinuteLimit) {
      throw new AppError({
        code: "AI_RATE_LIMIT_EXCEEDED",
        details: {
          limit: config.aiUserMinuteLimit,
          windowSeconds: 60,
        },
        message: "Too many AI requests were submitted.",
        statusCode: 429,
      });
    }
    if (input.voiceLeaseId !== undefined) {
      if (input.task !== "conversation")
        throw new AppError({
          code: "INVALID_VOICE_TASK",
          message: "Voice leases only support conversation.",
          statusCode: 400,
        });
      await access.assertVoiceLease(userId, input.voiceLeaseId);
    }
    const operationId = input.operationId ?? randomUUID();
    if (input.parentOperationId !== undefined && input.task !== "conversation")
      throw new AppError({
        code: "REPAIR_NOT_ALLOWED",
        message: "Only conversations support a linked repair.",
        statusCode: 400,
      });
    const kind =
      input.voiceLeaseId !== undefined || input.parentOperationId !== undefined
        ? "auxiliary"
        : ["conversation", "character_generation"].includes(input.task)
          ? "chat"
          : ["grammar_explain", "dictionary_explain", "speech_feedback"].includes(
                input.task,
              )
            ? "advanced"
            : "auxiliary";
    const hash = createHash("sha256")
      .update(
        JSON.stringify({
          task: input.task,
          messages: input.messages,
          responseFormat: input.responseFormat,
          maxOutputTokens: input.maxOutputTokens ?? null,
          voiceLeaseId: input.voiceLeaseId ?? null,
          parentOperationId: input.parentOperationId ?? null,
        }),
      )
      .digest("hex");
    const quota = await access.reserve(
      userId,
      operationId,
      hash,
      kind,
      1,
      input.parentOperationId,
      Math.ceil(route.timeoutMs * config.aiRetryMaxAttempts / 1000) + 30,    );
    let reservation = { requestId: operationId, startedAt: Date.now() };
    if (!quota.replay) {
      try {
        reservation = await repository.reserve(
          userId,
          route,
          100_000,
          limits.inputCharacters,
          operationId,
        );
      } catch (error) {
        await access.settle(userId, operationId, false);
        throw error;
      }
    }
    if (quota.replay && quota.result === null)
      throw new AppError({
        code: "OPERATION_RESULT_EXPIRED",
        message: "This request already completed. Please start a new operation.",
        statusCode: 409,
      });
    return {
      operationId,
      replay: quota.replay ? (quota.result as AiCompletion) : null,
      providerRequest: {
        onAttempt: () => repository.recordProviderAttempt(reservation.requestId),
        maxOutputTokens: limits.maxOutputTokens,
        messages: input.messages,
        responseFormat: input.responseFormat,
        route,
        ...(input.signal === undefined ? {} : { signal: input.signal }),
        userReference: userReference(userId),
      },
      ...reservation,
    };
  };

  const fail = async (
    userId: string,
    requestId: string,
    startedAt: number,
    operationId: string,
    error: unknown,
  ): Promise<void> => {
    await access.settle(userId, operationId, false);
    const identity = errorIdentity(error);
    await repository.fail(
      userId,
      requestId,
      startedAt,
      identity.code,
      identity.cancelled,
    );
  };

  return {
    complete: async (userId, input) => {
      const prepared = await prepare(userId, input);
      if (prepared.replay) return { ...prepared.replay, requestId: prepared.requestId };
      let completion: AiCompletion;
      try {
        completion = await deepSeek.complete(prepared.providerRequest);
      } catch (error) {
        await fail(
          userId,
          prepared.requestId,
          prepared.startedAt,
          prepared.operationId,
          error,
        );
        throw error;
      }
      await repository.succeed(
        userId,
        prepared.requestId,
        prepared.startedAt,
        completion.usage,
        completion.providerRequestId,
      );
      await access.settle(userId, prepared.operationId, true, completion);
      return {
        content: completion.content,
        model: completion.model,
        requestId: prepared.requestId,
        usage: completion.usage,
      };
    },
    stream: async (userId, input) => {
      const prepared = await prepare(userId, input);
      if (prepared.replay) {
        const replay = prepared.replay;
        return {
          requestId: prepared.requestId,
          events: (async function* (): AsyncGenerator<AiProviderStreamEvent> {
            await Promise.resolve();
            yield {
              type: "metadata",
              model: replay.model,
              providerRequestId: replay.providerRequestId,
            };
            yield { type: "delta", text: replay.content };
            yield { type: "usage", usage: replay.usage };
            yield { type: "done" };
          })(),
        };
      }
      let providerEvents: AsyncIterable<AiProviderStreamEvent>;
      try {
        providerEvents = await deepSeek.stream(prepared.providerRequest);
      } catch (error) {
        await fail(
          userId,
          prepared.requestId,
          prepared.startedAt,
          prepared.operationId,
          error,
        );
        throw error;
      }

      return {
        events: (async function* (): AsyncGenerator<AiProviderStreamEvent> {
          let finalized = false;
          let content = "";
          let providerRequestId: string | null = null;
          let usage: AiUsage = {
            inputTokens: 0,
            outputTokens: 0,
            totalTokens: 0,
          };
          try {
            for await (const event of providerEvents) {
              if (event.type === "delta") content += event.text;
              if (event.type === "done") continue;
              if (event.type === "metadata") {
                providerRequestId = event.providerRequestId;
              } else if (event.type === "usage") {
                usage = event.usage;
              }
              yield event;
            }
            await repository.succeed(
              userId,
              prepared.requestId,
              prepared.startedAt,
              usage,
              providerRequestId,
            );
            await access.settle(userId, prepared.operationId, true, {
              content,
              model: prepared.providerRequest.route.model,
              providerRequestId,
              usage,
            });
            finalized = true;
            yield { type: "done" };
          } catch (error) {
            await fail(
              userId,
              prepared.requestId,
              prepared.startedAt,
              prepared.operationId,
              error,
            );
            finalized = true;
            throw error;
          } finally {
            if (!finalized) {
              await access.settle(userId, prepared.operationId, false);
              await repository.fail(
                userId,
                prepared.requestId,
                prepared.startedAt,
                "AI_REQUEST_CANCELLED",
                true,
              );
            }
          }
        })(),
        requestId: prepared.requestId,
      };
    },
    resolveGuestUser: async (deviceId) => {
      const reference = guestReference(deviceId);
      return repository.ensureGuestPrincipal(guestUserId(reference), reference);
    },
    routeIdentity: async (task) => {
      const route = validateRuntimeRoute(
        await repository.route(task),
        config.aiDeepSeekAllowedModels,
      );
      return {
        configVersion: route.configVersion,
        model: route.model,
      };
    },
  };
}
