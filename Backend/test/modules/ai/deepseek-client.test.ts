import { describe, expect, it, vi } from "vitest";
import { loadConfig } from "../../../src/config/env.js";
import { createDeepSeekClient } from "../../../src/modules/ai/deepseek/client.js";
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
  model: "deepseek-v4-flash",
  provider: "deepseek",
  providerOptions: {},
  task: "quiz",
  temperature: 0.4,
  timeoutMs: 5000,
};

function request(): AiProviderRequest {
  return {
    maxOutputTokens: 700,
    messages: [{ content: "Create a quiz", role: "user" }],
    responseFormat: "json_object",
    route,
    userReference: "pseudonymous-user",
  };
}

function config() {
  return loadConfig({
    AI_RETRY_MAX_ATTEMPTS: "1",
    DEEPSEEK_API_KEY: "test-only-key",
    NODE_ENV: "test",
  });
}

describe("DeepSeek client", () => {
  it("verifies provider access and returns the deployment model catalog", async () => {
    const fetchMock = vi.fn<typeof fetch>().mockResolvedValue(
      Response.json({
        data: [
          { id: "deepseek-v4-flash", object: "model" },
          { id: "deepseek-v4-pro", object: "model" },
        ],
        object: "list",
      }),
    );
    const client = createDeepSeekClient(config(), fetchMock);

    await expect(client.availableModels()).resolves.toEqual([
      "deepseek-v4-flash",
      "deepseek-v4-pro",
    ]);
    expect(fetchMock).toHaveBeenCalledWith(
      new URL("https://api.deepseek.com/models"),
      expect.objectContaining({
        headers: {
          authorization: "Bearer test-only-key",
        },
        method: "GET",
      }),
    );
  });

  it("sends the configured model and normalizes a completion", async () => {
    const fetchMock = vi.fn<typeof fetch>();
    fetchMock.mockResolvedValue(
      new Response(
        JSON.stringify({
          choices: [{ message: { content: '{"answer":"B"}' } }],
          id: "provider-request-1",
          model: "deepseek-v4-flash",
          usage: {
            completion_tokens: 7,
            prompt_tokens: 11,
            total_tokens: 18,
          },
        }),
        {
          headers: { "content-type": "application/json" },
          status: 200,
        },
      ),
    );
    const client = createDeepSeekClient(config(), fetchMock);

    const protectedRequest = {
      ...request(),
      route: {
        ...route,
        providerOptions: {
          max_tokens: 999_999,
          messages: [],
          model: "injected-model",
          stream: true,
          user_id: "injected-user",
        },
      },
    };
    await expect(client.complete(protectedRequest)).resolves.toEqual({
      content: '{"answer":"B"}',
      model: "deepseek-v4-flash",
      providerRequestId: "provider-request-1",
      usage: {
        inputTokens: 11,
        outputTokens: 7,
        totalTokens: 18,
      },
    });

    const call = fetchMock.mock.calls[0];
    expect(call).toBeDefined();
    const options = call?.[1];
    if (typeof options?.body !== "string") {
      throw new Error("Expected a serialized request body");
    }
    const body = JSON.parse(options.body) as Record<string, unknown>;
    expect(body).toMatchObject({
      max_tokens: 700,
      model: "deepseek-v4-flash",
      response_format: { type: "json_object" },
      stream: false,
      user_id: "pseudonymous-user",
    });
    expect(new Headers(options.headers).get("authorization")).toBe(
      "Bearer test-only-key",
    );
  });

  it("parses SSE deltas and terminal usage", async () => {
    const fetchMock = vi.fn<typeof fetch>();
    fetchMock.mockResolvedValue(
      new Response(
        [
          'data: {"id":"stream-1","model":"deepseek-v4-flash","choices":[{"delta":{"content":"你"}}]}',
          "",
          'data: {"id":"stream-1","model":"deepseek-v4-flash","choices":[{"delta":{"content":"好"}}]}',
          "",
          'data: {"choices":[],"usage":{"prompt_tokens":4,"completion_tokens":2,"total_tokens":6}}',
          "",
          "data: [DONE]",
          "",
        ].join("\n"),
        {
          headers: { "content-type": "text/event-stream" },
          status: 200,
        },
      ),
    );
    const client = createDeepSeekClient(config(), fetchMock);
    const events = [];
    for await (const event of await client.stream(request())) {
      events.push(event);
    }

    expect(events).toEqual([
      {
        model: "deepseek-v4-flash",
        providerRequestId: "stream-1",
        type: "metadata",
      },
      { text: "你", type: "delta" },
      { text: "好", type: "delta" },
      {
        type: "usage",
        usage: { inputTokens: 4, outputTokens: 2, totalTokens: 6 },
      },
      { type: "done" },
    ]);
  });

  it("collects terminal usage after a downstream cancellation", async () => {
    const cancellation = new AbortController();
    let upstreamSignal: AbortSignal | undefined;
    const client = createDeepSeekClient(config(), async (_url, init) => {
      await Promise.resolve();
      upstreamSignal = init?.signal ?? undefined;
      return new Response(
        [
          'data: {"id":"drained","model":"deepseek-v4-flash","choices":[{"delta":{"content":"Hi"}}]}',
          "",
          'data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12,"prompt_tokens_details":{"cached_tokens":6}}}',
          "",
          "data: [DONE]",
          "",
          "",
        ].join("\n"),
      );
    });
    const events = [];
    for await (const event of await client.stream({
      ...request(),
      signal: cancellation.signal,
    })) {
      if (event.type === "delta") cancellation.abort();
      events.push(event);
    }
    expect(upstreamSignal?.aborted).toBe(false);
    expect(events).toContainEqual({
      type: "usage",
      usage: {
        inputTokens: 10,
        outputTokens: 2,
        totalTokens: 12,
        cacheHitTokens: 6,
        cacheMissTokens: 4,
      },
    });
    expect(events.at(-1)).toEqual({ type: "done" });
  });

  it("never dispatches an already cancelled stream", async () => {
    const fetchMock = vi.fn<typeof fetch>();
    const onAttempt = vi.fn();
    const client = createDeepSeekClient(config(), fetchMock);
    await expect(
      client.stream({ ...request(), onAttempt, signal: AbortSignal.abort() }),
    ).rejects.toMatchObject({ code: "AI_REQUEST_CANCELLED" });
    expect(onAttempt).not.toHaveBeenCalled();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it.each([
    [{ prompt_cache_hit_tokens: 6 }, 6, 4],
    [{ prompt_cache_miss_tokens: 4 }, 6, 4],
    [{ prompt_tokens_details: { cached_tokens: 0 } }, 0, 10],
  ])(
    "derives only the measured cache count's complement (%j)",
    async (cache, hit, miss) => {
      const client = createDeepSeekClient(config(), () =>
        Promise.resolve(
          Response.json({
            id: "cache",
            model: route.model,
            choices: [{ message: { content: "hello" } }],
            usage: {
              prompt_tokens: 10,
              completion_tokens: 2,
              total_tokens: 12,
              ...cache,
            },
          }),
        ),
      );
      expect((await client.complete(request())).usage).toMatchObject({
        cacheHitTokens: hit,
        cacheMissTokens: miss,
      });
    },
  );

  it("does not operate without a runtime secret", async () => {
    const client = createDeepSeekClient(
      loadConfig({ NODE_ENV: "test" }),
      vi.fn<typeof fetch>(),
    );

    expect(client.configured).toBe(false);
    await expect(client.complete(request())).rejects.toMatchObject({
      code: "AI_PROVIDER_NOT_CONFIGURED",
    });
  });
});
