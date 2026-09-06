import { setTimeout as delay } from "node:timers/promises";
import { z } from "zod";
import type { RuntimeConfig } from "../../../config/env.js";
import { AppError } from "../../../shared/errors.js";
import type {
  AiCompletion,
  AiProviderRequest,
  AiProviderStreamEvent,
  AiUsage,
} from "../types.js";

const usageSchema = z.object({
  prompt_cache_hit_tokens: z.number().int().nonnegative().optional(),
  prompt_cache_miss_tokens: z.number().int().nonnegative().optional(),
  completion_tokens: z.number().int().nonnegative(),
  prompt_tokens: z.number().int().nonnegative(),
  total_tokens: z.number().int().nonnegative(),
});

const completionSchema = z.object({
  choices: z
    .array(
      z.object({
        message: z.object({
          content: z.string(),
        }),
      }),
    )
    .min(1),
  id: z.string().optional(),
  model: z.string(),
  usage: usageSchema,
});

const streamChunkSchema = z.object({
  choices: z.array(
    z.object({
      delta: z.object({
        content: z.string().nullish(),
      }),
    }),
  ),
  error: z
    .object({
      code: z.string().optional(),
    })
    .optional(),
  id: z.string().optional(),
  model: z.string().optional(),
  usage: usageSchema.nullish(),
});
const modelListSchema = z.object({
  data: z.array(
    z.object({
      id: z.string().min(1),
    }),
  ),
});

function mapUsage(usage: z.infer<typeof usageSchema>): AiUsage {
  return {
    ...(usage.prompt_cache_hit_tokens === undefined
      ? {}
      : { cacheHitTokens: usage.prompt_cache_hit_tokens }),
    ...(usage.prompt_cache_miss_tokens === undefined
      ? {}
      : { cacheMissTokens: usage.prompt_cache_miss_tokens }),
    inputTokens: usage.prompt_tokens,
    outputTokens: usage.completion_tokens,
    totalTokens: usage.total_tokens,
  };
}

function upstreamError(status: number): AppError {
  if (status === 429) {
    return new AppError({
      code: "AI_UPSTREAM_RATE_LIMITED",
      message: "The AI provider is temporarily rate limited.",
      statusCode: 503,
    });
  }
  if (status >= 400 && status < 500) {
    return new AppError({
      code: "AI_UPSTREAM_REJECTED",
      message: "The AI provider rejected the request.",
      statusCode: 502,
    });
  }
  return new AppError({
    code: "AI_UPSTREAM_UNAVAILABLE",
    message: "The AI provider is temporarily unavailable.",
    statusCode: 502,
  });
}

function protocolError(cause?: unknown): AppError {
  return new AppError({
    cause,
    code: "AI_UPSTREAM_PROTOCOL_ERROR",
    message: "The AI provider returned an invalid response.",
    statusCode: 502,
  });
}

function requestBody(request: AiProviderRequest, stream: boolean): unknown {
  return {
    ...request.route.providerOptions,
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
    user_id: request.userReference,
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
      if (data.length > 0) {
        yield data;
      }
    }
  }
  buffer += decoder.decode();
  const trailing = buffer
    .split(/\r?\n/)
    .filter((line) => line.startsWith("data:"))
    .map((line) => line.slice(5).trimStart())
    .join("\n");
  if (trailing.length > 0) {
    yield trailing;
  }
}

export type DeepSeekClient = Readonly<{
  complete: (request: AiProviderRequest) => Promise<AiCompletion>;
  configured: boolean;
  stream: (request: AiProviderRequest) => Promise<AsyncIterable<AiProviderStreamEvent>>;
}>;

export type DeepSeekOperationalClient = DeepSeekClient &
  Readonly<{
    availableModels: () => Promise<readonly string[]>;
  }>;

export function createDeepSeekClient(
  config: RuntimeConfig,
  fetchImplementation: typeof fetch = fetch,
): DeepSeekOperationalClient {
  const completionsEndpoint = new URL(
    "chat/completions",
    config.deepSeekBaseUrl.endsWith("/")
      ? config.deepSeekBaseUrl
      : `${config.deepSeekBaseUrl}/`,
  );
  const modelsEndpoint = new URL(
    "models",
    config.deepSeekBaseUrl.endsWith("/")
      ? config.deepSeekBaseUrl
      : `${config.deepSeekBaseUrl}/`,
  );

  const authorization = (): string => {
    if (config.deepSeekApiKey === undefined) {
      throw new AppError({
        code: "AI_PROVIDER_NOT_CONFIGURED",
        message: "The AI provider is not configured.",
        statusCode: 503,
      });
    }
    return `Bearer ${config.deepSeekApiKey}`;
  };

  const execute = async (
    request: AiProviderRequest,
    stream: boolean,
  ): Promise<Response> => {
    let lastError: unknown;
    for (let attempt = 1; attempt <= config.aiRetryMaxAttempts; attempt += 1) {
      await request.onAttempt?.();
      const timeoutSignal = AbortSignal.timeout(request.route.timeoutMs);
      const signal =
        request.signal === undefined
          ? timeoutSignal
          : AbortSignal.any([request.signal, timeoutSignal]);
      try {
        const response = await fetchImplementation(completionsEndpoint, {
          body: JSON.stringify(requestBody(request, stream)),
          headers: {
            authorization: authorization(),
            "content-type": "application/json",
          },
          method: "POST",
          signal,
        });
        if (response.ok) {
          return response;
        }
        lastError = upstreamError(response.status);
        if (
          attempt === config.aiRetryMaxAttempts ||
          (response.status !== 429 && response.status < 500)
        ) {
          throw lastError;
        }
      } catch (error) {
        if (request.signal?.aborted === true) {
          throw new AppError({
            code: "AI_REQUEST_CANCELLED",
            message: "The AI request was cancelled.",
            statusCode: 499,
          });
        }
        if (timeoutSignal.aborted) {
          throw new AppError({
            code: "AI_UPSTREAM_TIMEOUT",
            message: "The AI provider timed out.",
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
        if (attempt === config.aiRetryMaxAttempts) {
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
    availableModels: async () => {
      const authorizationHeader = authorization();
      let response: Response;
      try {
        response = await fetchImplementation(modelsEndpoint, {
          headers: {
            authorization: authorizationHeader,
          },
          method: "GET",
          signal: AbortSignal.timeout(Math.min(config.requestTimeoutMs, 10_000)),
        });
      } catch {
        throw upstreamError(502);
      }
      if (!response.ok) {
        throw upstreamError(response.status);
      }
      let decoded: unknown;
      try {
        decoded = await response.json();
      } catch (error) {
        throw protocolError(error);
      }
      const result = modelListSchema.safeParse(decoded);
      if (!result.success) {
        throw protocolError(result.error);
      }
      return result.data.data.map((model) => model.id);
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
      if (!result.success) {
        throw protocolError(result.error);
      }
      const firstChoice = result.data.choices[0];
      if (firstChoice === undefined) {
        throw protocolError();
      }
      return {
        content: firstChoice.message.content,
        model: result.data.model,
        providerRequestId: result.data.id ?? null,
        usage: mapUsage(result.data.usage),
      };
    },
    configured: config.deepSeekApiKey !== undefined,
    stream: async (request) => {
      const response = await execute(request, true);
      if (response.body === null) {
        throw protocolError();
      }
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
          if (!chunk.success) {
            throw protocolError(chunk.error);
          }
          if (chunk.data.error !== undefined) {
            throw upstreamError(502);
          }
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
            yield {
              type: "usage",
              usage: mapUsage(chunk.data.usage),
            };
          }
        }
        if (!doneSent) {
          yield { type: "done" };
        }
      })();
    },
  };
}
