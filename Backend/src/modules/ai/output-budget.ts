import type { AiRouteConfig } from "./types.js";

/** Reasoning models count thinking against max_tokens, before any visible reply. */
export function outputTokenBudget(
  requested: number | undefined,
  route: AiRouteConfig,
): number {
  const minimum =
    route.provider === "openrouter" &&
    route.task === "conversation" &&
    route.model.startsWith("z-ai/glm-")
      ? 512
      : 1;
  return Math.min(
    Math.max(requested ?? route.maxOutputTokens, minimum),
    route.maxOutputTokens,
  );
}
