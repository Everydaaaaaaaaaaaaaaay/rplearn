import { createHash } from "node:crypto";
import { setTimeout as delay } from "node:timers/promises";
import { z } from "zod";
import type { RuntimeConfig } from "../../../config/env.js";
import { AppError } from "../../../shared/errors.js";
import type {
  AiProviderClient,
  AiProviderRequest,
  AiProviderStreamEvent,
  AiUsage,
} from "../types.js";

const decimalPrice = z.string().regex(/^-?\d+(?:\.\d+)?$/);
const usageSchema = z.object({
  completion_tokens: z.number().int().nonnegative(),
  cost: z.number().nonnegative().nullish(),
  prompt_tokens: z.number().int().nonnegative(),
  prompt_tokens_details: z
    .object({ cached_tokens: z.number().int().nonnegative().optional() })
    .loose()
    .nullish(),
  total_tokens: z.number().int().nonnegative(),
});
const completionSchema = z.object({
  choices: z.array(z.object({ message: z.object({ content: z.string() }) })).min(1),
  id: z.string().optional(),
  model: z.string(),
  usage: usageSchema,
});
const streamChunkSchema = z.object({
  choices: z.array(
    z.object({ delta: z.object({ content: z.string().nullish() }).loose() }),
  ),
  error: z.object({ code: z.union([z.number(), z.string()]).optional() }).optional(),
  id: z.string().optional(),
  model: z.string().optional(),
  usage: usageSchema.nullish(),
});
const modelListSchema = z.object({
  data: z.array(
    z.object({
      architecture: z.record(z.string(), z.unknown()).optional(),
      context_length: z.number().int().positive().nullish(),
      id: z.string().min(3).max(192),
      name: z.string().min(1).max(300),
      pricing: z.object({
        completion: decimalPrice,
        input_cache_read: decimalPrice.nullish(),
        prompt: decimalPrice,
      }),
      supported_parameters: z.array(z.string().min(1).max(128)).default([]),
    }),
  ),
});

export type OpenRouterModel = Readonly<{
  architecture: Readonly<Record<string, unknown>>;
  cachedInputPriceUsd: string | null;
  completionPriceUsd: string;
  contextLength: number | null;
  id: string;
  name: string;
  promptPriceUsd: string;
  supportedParameters: readonly string[];
}>;

function costString(value: number): string {
  return value.toFixed(12).replace(/\.?0+$/, "") || "0";
}

function mapUsage(usage: z.infer<typeof usageSchema>): AiUsage {
  const cached = Math.min(
    usage.prompt_tokens,
    usage.prompt_tokens_details?.cached_tokens ?? 0,
  );
  return {
    cacheHitTokens: cached,
    cacheMissTokens: usage.prompt_tokens - cached,
    inputTokens: usage.prompt_tokens,
    outputTokens: usage.completion_tokens,
    ...(usage.cost === undefined || usage.cost === null
      ? {}
      : { providerCostUsd: costString(usage.cost) }),
    totalTokens: usage.total_tokens,
  };
}

function upstreamError(status: number): AppError {
  if (status === 429) {
    return new AppError({
      code: "AI_UPSTREAM_RATE_LIMITED",
      message: "OpenRouter is temporarily rate limited.",
      statusCode: 503,
    });
  }
  if (status >= 400 && status < 500) {
    return new AppError({
      code: "AI_UPSTREAM_REJECTED",
      message: "OpenRouter rejected the request.",
      statusCode: 502,
    });
  }
  return new AppError({
    code: "AI_UPSTREAM_UNAVAILABLE",
    message: "OpenRouter is temporarily unavailable.",
    statusCode: 502,
  });
}

function protocolError(cause?: unknown): AppError {
  return new AppError({
    cause,
    code: "AI_UPSTREAM_PROTOCOL_ERROR",
    message: "OpenRouter returned an invalid response.",
    statusCode: 502,
  });
}

function requestBody(request: AiProviderRequest, stream: boolean): unknown {
  return {
    ...request.route.providerOptions,
    // Opaque, stable per user/task/model. Dynamic opening messages must not move
    // an ongoing workflow between providers and discard a warm prefix cache.
    session_id: createHash("sha256")
      .update(
        `lingotrip-cache-v1:${request.userReference}:${request.route.task}:${request.route.model}`,
      )
      .digest("hex"),
    max_tokens: request.maxOutputTokens,
    messages: request.messages,
    model: request.route.model,
    ...(request.responseFormat === "json_object"
      ? { response_format: { type: "json_object" } }
      : {}),
    stream,
    ...(stream ? { stream_options: { include_usage: true } } : {}),
    ...(request.route.temperature === null
      ? {}
      : { temperature: request.route.temperature }),
    user: request.userReference,
  };
}

async function* dataEvents(body: ReadableStream<Uint8Array>): AsyncGenerator<string> {
  const decoder = new TextDecoder();
  let buffer = "";
  for await (const chunk of body) {
    buffer += decoder.decode(chunk, { stream: true });
    const blocks = buffer.split(/\r?\n\r?\n/);
    buffer = blocks.pop() ?? "";
    for (const block of blocks) {
      const data = block
        .split(/\r?\n/)
        .filter((line) => line.startsWith("data:"))
        .map((line) => line.slice(5).trimStart())
        .join("\n");
      if (data.length > 0) yield data;
    }
  }
  buffer += decoder.decode();
  const trailing = buffer
    .split(/\r?\n/)
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).trimStart())
    .join("\n");
  if (trailing.length > 0) yield trailing;
}

export type OpenRouterClient = AiProviderClient &
  Readonly<{ models: () => Promise<readonly OpenRouterModel[]> }>;

export function createOpenRouterClient(
  config: RuntimeConfig,
  fetchImplementation: typeof fetch = fetch,
): OpenRouterClient {
  const root = config.openRouterBaseUrl.endsWith("/")
    ? config.openRouterBaseUrl
    : `${config.openRouterBaseUrl}/`;
  const completionsEndpoint = new URL("chat/completions", root);
  const modelsEndpoint = new URL("models", root);
  const headers = (requiresKey: boolean): Record<string, string> => {
    if (requiresKey && config.openRouterApiKey === undefined) {
      throw new AppError({
        code: "AI_PROVIDER_NOT_CONFIGURED",
        message: "OpenRouter is not configured.",
        statusCode: 503,
      });
    }
    return {
      ...(config.openRouterApiKey === undefined
        ? {}
        : { authorization: `Bearer ${config.openRouterApiKey}` }),
      "content-type": "application/json",
      ...(config.openRouterSiteUrl === undefined
        ? {}
        : { "http-referer": config.openRouterSiteUrl }),
      "x-openrouter-title": config.openRouterAppName,
    };
  };

  const execute = async (
    request: AiProviderRequest,
    stream: boolean,
  ): Promise<Response> => {
    let lastError: unknown;
    const maxAttempts = request.maxAttempts ?? config.aiRetryMaxAttempts;
    for (let attempt = 1; attempt <= maxAttempts; attempt += 1) {
      // Cancel before dispatch, but once a streamed request is sent, drain its
      // bounded response through terminal usage even if the app disconnects.
      // Otherwise a successful generation can permanently strand its credit hold.
      if (request.signal?.aborted) {
        throw new AppError({
          code: "AI_REQUEST_CANCELLED",
          message: "The AI request was cancelled.",
          statusCode: 499,
        });
      }
      await request.onAttempt?.();
      const timeoutSignal = AbortSignal.timeout(request.route.timeoutMs);
      const signal =
        stream || request.signal === undefined
          ? timeoutSignal
          : AbortSignal.any([request.signal, timeoutSignal]);
      try {
        const response = await fetchImplementation(completionsEndpoint, {
          body: JSON.stringify(requestBody(request, stream)),
          headers: headers(true),
          method: "POST",
          signal,
        });
        if (response.ok) return response;
        lastError = upstreamError(response.status);
        if (
          attempt === maxAttempts ||
          (response.status !== 429 && response.status < 500)
        ) {
          throw lastError;
        }
      } catch (error) {
        if (!stream && request.signal?.aborted === true) {
          throw new AppError({
            code: "AI_REQUEST_CANCELLED",
            message: "The AI request was cancelled.",
            statusCode: 499,
          });
        }
        if (timeoutSignal.aborted) {
          throw new AppError({
            code: "AI_UPSTREAM_TIMEOUT",
            message: "OpenRouter timed out.",
            statusCode: 504,
          });
        }
        lastError = error;
        if (
          error instanceof AppError &&
          error.code !== "AI_UPSTREAM_UNAVAILABLE" &&
          error.code !== "AI_UPSTREAM_RATE_LIMITED"
        ) {
          throw error;
        }
        if (attempt === maxAttempts) {
          throw error instanceof AppError ? error : upstreamError(502);
        }
      }
      await delay(100 * 2 ** (attempt - 1), undefined, {
        signal: request.signal,
      }).catch(() => {
        throw new AppError({
          code: "AI_REQUEST_CANCELLED",
          message: "The AI request was cancelled.",
          statusCode: 499,
        });
      });
    }
    throw lastError instanceof AppError ? lastError : upstreamError(502);
  };

  return {
    configured: config.openRouterApiKey !== undefined,
    models: async () => {
      let response: Response;
      try {
        response = await fetchImplementation(modelsEndpoint, {
          headers: headers(false),
          method: "GET",
          signal: AbortSignal.timeout(Math.min(config.requestTimeoutMs, 15_000)),
        });
      } catch {
        throw upstreamError(502);
      }
      if (!response.ok) throw upstreamError(response.status);
      let decoded: unknown;
      try {
        decoded = await response.json();
      } catch (error) {
        throw protocolError(error);
      }
      const result = modelListSchema.safeParse(decoded);
      if (!result.success) throw protocolError(result.error);
      return result.data.data.map((model) => ({
        architecture: model.architecture ?? {},
        cachedInputPriceUsd: model.pricing.input_cache_read ?? null,
        completionPriceUsd: model.pricing.completion,
        contextLength: model.context_length ?? null,
        id: model.id,
        name: model.name,
        promptPriceUsd: model.pricing.prompt,
        supportedParameters: model.supported_parameters,
      }));
    },
    complete: async (request) => {
      const response = await execute(request, false);
      let decoded: unknown;
      try {
        decoded = await response.json();
      } catch (error) {
        throw protocolError(error);
      }
      const result = completionSchema.safeParse(decoded);
      if (!result.success) throw protocolError(result.error);
      const first = result.data.choices[0];
      if (first === undefined) throw protocolError();
      return {
        content: first.message.content,
        model: result.data.model,
        providerRequestId: result.data.id ?? null,
        usage: mapUsage(result.data.usage),
      };
    },
    stream: async (request) => {
      const response = await execute(request, true);
      if (response.body === null) throw protocolError();
      const body = response.body;
      return (async function* (): AsyncGenerator<AiProviderStreamEvent> {
        let metadataSent = false;
        let doneSent = false;
        for await (const data of dataEvents(body)) {
          if (data === "[DONE]") {
            doneSent = true;
            yield { type: "done" };
            break;
          }
          let decoded: unknown;
          try {
            decoded = JSON.parse(data) as unknown;
          } catch (error) {
            throw protocolError(error);
          }
          const chunk = streamChunkSchema.safeParse(decoded);
          if (!chunk.success) throw protocolError(chunk.error);
          if (chunk.data.error !== undefined) throw upstreamError(502);
          if (!metadataSent) {
            metadataSent = true;
            yield {
              model: chunk.data.model ?? request.route.model,
              providerRequestId: chunk.data.id ?? null,
              type: "metadata",
            };
          }
          for (const choice of chunk.data.choices) {
            const text = choice.delta.content;
            if (text !== undefined && text !== null && text.length > 0) {
              yield { text, type: "delta" };
            }
          }
          if (chunk.data.usage !== undefined && chunk.data.usage !== null) {
            yield { type: "usage", usage: mapUsage(chunk.data.usage) };
          }
        }
        if (!doneSent) throw protocolError();
      })();
    },
  };
}
