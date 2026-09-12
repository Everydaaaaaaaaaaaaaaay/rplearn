import type { AiRouteConfig } from "./types.js";

/** Reasoning models count thinking against max_tokens, before any visible reply. */
export function outputTokenBudget(
  requested: number | undefined,
  route: AiRouteConfig,
): number {
  const minimum =
    route.provider === "openrouter" &&
    ["conversation", "proactive_message", "coach_review"].includes(route.task) &&
    route.model.startsWith("z-ai/glm-")
      ? route.task === "coach_review"
        ? 1536
        : 512
      : 1;
  return Math.min(
    Math.max(requested ?? route.maxOutputTokens, minimum),
    route.maxOutputTokens,
  );
}
