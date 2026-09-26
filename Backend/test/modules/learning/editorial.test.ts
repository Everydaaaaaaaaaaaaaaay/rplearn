import { describe, expect, it, vi } from "vitest";
import { loadConfig } from "../../../src/config/env.js";
import { createLearningEditorialCompletion } from "../../../src/modules/ai/editorial-service.js";
import type { AiProviderRequest } from "../../../src/modules/ai/types.js";

describe("公共课程供应商请求", () => {
  it("没有 OpenRouter 凭据时明确失败，不暗中回退到 DeepSeek", () => {
    expect(() =>
      createLearningEditorialCompletion(
        loadConfig({ NODE_ENV: "test", AI_DEEPSEEK_API_KEY: "fixture-only" }),
      ),
    ).toThrow("OpenRouter");
  });
  it("使用指定 OpenRouter Luna、固定公开引用、限制每次请求且不走用户计费", async () => {
    const complete = vi.fn((request: AiProviderRequest) =>
      Promise.resolve({
        content: JSON.stringify(request.messages),
        model: "fixture",
        providerRequestId: null,
        usage: { inputTokens: 1, outputTokens: 1, totalTokens: 2 },
      }),
    );
    const provider = { configured: true, complete, stream: vi.fn() };
    const completion = createLearningEditorialCompletion(
      loadConfig({ NODE_ENV: "test" }),
      provider,
    );
    await completion({
      phase: "review",
      messages: [{ role: "system", content: "只审核公开内容。" }],
    });
    expect(complete.mock.calls[0]?.[0]).toMatchObject({
      maxAttempts: 1,
      userReference: "public-learning-catalog",
      maxOutputTokens: 16000,
      route: {
        provider: "openrouter",
        model: "openai/gpt-6-luna",
        temperature: null,
        providerOptions: {
          provider: { require_parameters: true },
          reasoning: { effort: "medium", exclude: true },
        },
        timeoutMs: 120000,
      },
    });
    await expect(
      completion({
        phase: "author",
        messages: [{ role: "user", content: "a".repeat(180001) }],
      }),
    ).rejects.toThrow();
    expect(complete).toHaveBeenCalledTimes(1);
  });
});
