import type { AiRouteConfig } from "./types.js";

/** Reasoning models count thinking against max_tokens, before any visible reply. */
export function outputTokenBudget(
  requested: number | undefined,
  route: AiRouteConfig,
): number {
  // GLM on OpenRouter cannot disable reasoning ("Reasoning is mandatory for this endpoint"),
  // so short JSON answers still need room for thinking before any visible body.
  const glmReasoningFloor =
    route.provider === "openrouter" && route.model.startsWith("z-ai/glm-");
  const minimum = !glmReasoningFloor
    ? 1
    : [
          "coach_review",
          "memory_summary",
          "dictionary_explain",
          "grammar_explain",
        ].includes(route.task)
      ? 1536
      : 512;
  return Math.min(
    Math.max(requested ?? route.maxOutputTokens, minimum),
    route.maxOutputTokens,
  );
}
