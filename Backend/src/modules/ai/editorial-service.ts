import type { RuntimeConfig } from "../../config/env.js";
import type { AiMessage, AiProviderClient } from "./types.js";
import { createDeepSeekClient } from "./deepseek/client.js";

/** 公共课程生产不经过用户聊天扣费；调用预算与审计由学习生成仓库持有。 */
export function createLearningEditorialCompletion(
  config: RuntimeConfig,
  provider: AiProviderClient = createDeepSeekClient(config),
) {
  const model = config.aiDeepSeekAllowedModels[0];
  if (!provider.configured || !model)
    throw new Error("学习内容生成尚未配置可用供应商。");
  return async (
    input: Readonly<{
      phase: "author" | "review";
      messages: readonly AiMessage[];
      signal?: AbortSignal;
    }>,
  ) => {
    if (input.messages.reduce((sum, m) => sum + m.content.length, 0) > 180_000)
      throw new Error("课程生成输入超出已配置上限。");
    return provider.complete({
      messages: input.messages,
      responseFormat: "json_object",
      maxOutputTokens: 9000,
      maxAttempts: 1,
      userReference: "public-learning-catalog",
      ...(input.signal ? { signal: input.signal } : {}),
      route: {
        task: `learning_${input.phase}`,
        provider: "deepseek",
        model,
        allowJsonResponse: true,
        configVersion: 1,
        maxInputCharacters: 180_000,
        maxMessages: 2,
        maxOutputTokens: 9000,
        providerOptions: { thinking: { type: "disabled" } },
        temperature: input.phase === "author" ? 0.65 : 0,
        timeoutMs: 90_000,
      },
    });
  };
}
