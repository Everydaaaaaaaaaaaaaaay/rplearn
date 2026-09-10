import { describe, expect, it, vi } from "vitest";
import { loadConfig } from "../../../src/config/env.js";
import { createOpenRouterClient } from "../../../src/modules/ai/openrouter/client.js";
import type {
  AiProviderRequest,
  AiRouteConfig,
} from "../../../src/modules/ai/types.js";

const route: AiRouteConfig = {
  allowJsonResponse: true,
  configVersion: 1,
  maxInputCharacters: 10_000,
  maxMessages: 10,
  maxOutputTokens: 800,
  model: "inclusionai/ling-3.0-flash",
  provider: "openrouter",
  providerOptions: { provider: { require_parameters: true } },
  task: "quiz",
  temperature: 0.4,
  timeoutMs: 5000,
};

function config(withKey = true) {
  return loadConfig({
    AI_RETRY_MAX_ATTEMPTS: "1",
    NODE_ENV: "test",
    ...(withKey
      ? {
          OPENROUTER_API_KEY: "test-openrouter-key",
          OPENROUTER_SITE_URL: "https://lingotrip.example",
          OPENROUTER_USD_TO_CNY: "7.2",
        }
      : {}),
  });
}

function request(): AiProviderRequest {
  return {
    maxOutputTokens: 700,
    messages: [{ content: "Create a quiz", role: "user" }],
    responseFormat: "json_object",
    route,
    userReference: "pseudonymous-user",
  };
}

describe("OpenRouter client", () => {
  it("loads and normalizes the public model catalog", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json({
        data: [
          {
            architecture: { input_modalities: ["text"], output_modalities: ["text"] },
            context_length: 262144,
            id: "inclusionai/ling-3.0-flash",
            name: "inclusionAI: Ling 3.0 Flash",
            pricing: {
              completion: "0.000000063",
              input_cache_read: "0.0000000042",
              prompt: "0.000000021",
            },
            supported_parameters: ["response_format", "temperature"],
          },
        ],
      }),
    );
    const client = createOpenRouterClient(config(false), fetchMock);
    await expect(client.models()).resolves.toEqual([
      expect.objectContaining({
        contextLength: 262144,
        id: "inclusionai/ling-3.0-flash",
        promptPriceUsd: "0.000000021",
      }),
    ]);
    expect(fetchMock).toHaveBeenCalledWith(
      new URL("https://openrouter.ai/api/v1/models"),
      expect.objectContaining({ method: "GET" }),
    );
  });

  it("protects controlled fields and records cache and exact upstream cost", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json({
        choices: [{ message: { content: '{"answer":"B"}' } }],
        id: "generation-1",
        model: "inclusionai/ling-3.0-flash",
        usage: {
          completion_tokens: 7,
          cost: 0.000123,
          prompt_tokens: 11,
          prompt_tokens_details: { cached_tokens: 8 },
          total_tokens: 18,
        },
      }),
    );
    const client = createOpenRouterClient(config(), fetchMock);
    await expect(client.complete(request())).resolves.toEqual({
      content: '{"answer":"B"}',
      model: "inclusionai/ling-3.0-flash",
      providerRequestId: "generation-1",
      usage: {
        cacheHitTokens: 8,
        cacheMissTokens: 3,
        inputTokens: 11,
        outputTokens: 7,
        providerCostUsd: "0.000123",
        totalTokens: 18,
      },
    });
    const options = fetchMock.mock.calls[0]?.[1];
    if (typeof options?.body !== "string") throw new Error("missing request body");
    expect(JSON.parse(options.body)).toMatchObject({
      max_tokens: 700,
      model: "inclusionai/ling-3.0-flash",
      provider: { require_parameters: true },
      response_format: { type: "json_object" },
      stream: false,
      user: "pseudonymous-user",
    });
    const headers = new Headers(options.headers);
    expect(headers.get("authorization")).toBe("Bearer test-openrouter-key");
    expect(headers.get("http-referer")).toBe("https://lingotrip.example");
    expect(headers.get("x-openrouter-title")).toBe("LingoTrip");
  });

  it("keeps usage billable from catalog prices when upstream cost is null", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json({
        choices: [{ message: { content: "Fallback-priced response" } }],
        model: "inclusionai/ling-3.0-flash",
        usage: {
          completion_tokens: 2,
          cost: null,
          prompt_tokens: 4,
          prompt_tokens_details: null,
          total_tokens: 6,
        },
      }),
    );
    const client = createOpenRouterClient(config(), fetchMock);

    const completion = await client.complete(request());
    expect(completion).toMatchObject({
      usage: {
        cacheHitTokens: 0,
        cacheMissTokens: 4,
        inputTokens: 4,
        outputTokens: 2,
        totalTokens: 6,
      },
    });
    expect(completion.usage).not.toHaveProperty("providerCostUsd");
  });

  it("parses streamed output and refuses completions without a secret", async () => {
    const fetchMock = vi
      .fn<typeof fetch>()
      .mockResolvedValue(
        new Response(
          [
            'data: {"id":"stream-1","model":"inclusionai/ling-3.0-flash","choices":[{"delta":{"content":"Hi"}}]}',
            "",
            'data: {"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6,"cost":0.00002}}',
            "",
            "data: [DONE]",
            "",
          ].join("\n"),
        ),
      );
    const client = createOpenRouterClient(config(), fetchMock);
    const events = [];
    for await (const event of await client.stream({
      ...request(),
      responseFormat: "text",
    })) {
      events.push(event);
    }
    expect(events).toEqual([
      {
        model: "inclusionai/ling-3.0-flash",
        providerRequestId: "stream-1",
        type: "metadata",
      },
      { text: "Hi", type: "delta" },
      {
        type: "usage",
        usage: {
          cacheHitTokens: 0,
          cacheMissTokens: 4,
          inputTokens: 4,
          outputTokens: 2,
          providerCostUsd: "0.00002",
          totalTokens: 6,
        },
      },
      { type: "done" },
    ]);

    const unconfigured = createOpenRouterClient(config(false), vi.fn<typeof fetch>());
    expect(unconfigured.configured).toBe(false);
    await expect(unconfigured.complete(request())).rejects.toMatchObject({
      code: "AI_PROVIDER_NOT_CONFIGURED",
    });
  });
});
