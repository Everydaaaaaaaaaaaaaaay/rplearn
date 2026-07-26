import { createHmac } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import type { RedisResource } from "../../infrastructure/redis/client.js";
import { AppError } from "../../shared/errors.js";
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

function dailyLimit(
  features: Readonly<Record<string, boolean | number | string>>,
): number {
  const value = features.aiDailyRequests;
  return typeof value === "number" && Number.isInteger(value)
    ? Math.max(1, Math.min(10_000, value))
    : 30;
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
  billingService: BillingService,
  deepSeek: DeepSeekClient,
): AiService {
  const repository = new AiRepository(database);
  const userReference = (userId: string): string =>
    createHmac("sha256", config.authTokenHashPepper)
      .update(`ai-user:${userId}`)
      .digest("hex");

  const prepare = async (
    userId: string,
    input: AiRequestInput,
  ): Promise<
    Readonly<{
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
    const entitlements = await billingService.getEntitlements(userId);
    const reservation = await repository.reserve(
      userId,
      route,
      dailyLimit(entitlements.featureFlags),
      limits.inputCharacters,
    );
    return {
      providerRequest: {
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
    error: unknown,
  ): Promise<void> => {
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
      let completion: AiCompletion;
      try {
        completion = await deepSeek.complete(prepared.providerRequest);
      } catch (error) {
        await fail(userId, prepared.requestId, prepared.startedAt, error);
        throw error;
      }
      await repository.succeed(
        userId,
        prepared.requestId,
        prepared.startedAt,
        completion.usage,
        completion.providerRequestId,
      );
      return {
        content: completion.content,
        model: completion.model,
        requestId: prepared.requestId,
        usage: completion.usage,
      };
    },
    stream: async (userId, input) => {
      const prepared = await prepare(userId, input);
      let providerEvents: AsyncIterable<AiProviderStreamEvent>;
      try {
        providerEvents = await deepSeek.stream(prepared.providerRequest);
      } catch (error) {
        await fail(userId, prepared.requestId, prepared.startedAt, error);
        throw error;
      }

      return {
        events: (async function* (): AsyncGenerator<AiProviderStreamEvent> {
          let finalized = false;
          let providerRequestId: string | null = null;
          let usage: AiUsage = {
            inputTokens: 0,
            outputTokens: 0,
            totalTokens: 0,
          };
          try {
            for await (const event of providerEvents) {
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
            finalized = true;
          } catch (error) {
            await fail(userId, prepared.requestId, prepared.startedAt, error);
            finalized = true;
            throw error;
          } finally {
            if (!finalized) {
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
  };
}
