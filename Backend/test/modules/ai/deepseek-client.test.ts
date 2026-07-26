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
