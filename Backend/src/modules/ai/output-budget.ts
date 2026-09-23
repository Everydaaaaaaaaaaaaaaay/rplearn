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
  // Production reasoning-only failures exhausted 512 tokens before any chat text.
  // This is a ceiling, not a target length; retain the route cap and short-reply prompt.
  const minimum = !glmReasoningFloor
    ? 1
    : route.task === "conversation"
      ? 2048
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
