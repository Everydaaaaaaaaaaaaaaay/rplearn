import type { RuntimeConfig } from "../../config/env.js";
import type { AiMessage, AiProviderClient } from "./types.js";
import { createOpenRouterClient } from "./openrouter/client.js";

/** 公共课程生产不经过用户聊天扣费；调用预算与审计由学习生成仓库持有。 */
export function createLearningEditorialCompletion(
  config: RuntimeConfig,
  provider: AiProviderClient = createOpenRouterClient(config),
) {
  const model = config.learningGenerationModel;
  if (!provider.configured || !model)
    throw new Error("学习内容生成尚未配置可用 OpenRouter 供应商。");
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
      maxOutputTokens: 16000,
      maxAttempts: 1,
      userReference: "public-learning-catalog",
      ...(input.signal ? { signal: input.signal } : {}),
      route: {
        task: `learning_${input.phase}`,
        provider: "openrouter",
        model,
        allowJsonResponse: true,
        configVersion: 2,
        maxInputCharacters: 180_000,
        maxMessages: 2,
        maxOutputTokens: 16000,
        providerOptions: {
          provider: { require_parameters: true },
          reasoning: { effort: "medium", exclude: true },
        },
        // Luna 不声明支持 temperature；保留中等推理并只消费最终结构化答案。
        temperature: null,
        timeoutMs: 120_000,
      },
    });
  };
}
