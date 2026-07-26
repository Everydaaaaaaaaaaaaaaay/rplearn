import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import type { AiRouteConfig, AiRouteSettings } from "./types.js";

const stopSchema = z.union([
  z.string().min(1).max(200),
  z.array(z.string().min(1).max(200)).min(1).max(16),
]);

export const deepSeekProviderOptionsSchema = z
  .object({
    frequency_penalty: z.number().min(-2).max(2).optional(),
    presence_penalty: z.number().min(-2).max(2).optional(),
    reasoning_effort: z.enum(["high", "max"]).optional(),
    seed: z.number().int().optional(),
    stop: stopSchema.nullable().optional(),
    thinking: z
      .object({
        type: z.enum(["enabled", "disabled"]),
      })
      .strict()
      .optional(),
    top_p: z.number().min(0).max(1).optional(),
  })
  .strict();

export const aiRouteSettingsSchema = z
  .object({
    allowJsonResponse: z.boolean(),
    enabled: z.boolean(),
    maxInputCharacters: z.number().int().min(1).max(500_000),
    maxMessages: z.number().int().min(1).max(100),
    maxOutputTokens: z.number().int().min(1).max(384_000),
    model: z.string().regex(/^[a-zA-Z0-9][a-zA-Z0-9._-]{1,127}$/),
    provider: z.literal("deepseek"),
    providerOptions: deepSeekProviderOptionsSchema,
    temperature: z.number().min(0).max(2).nullable(),
    timeoutMs: z.number().int().min(1_000).max(120_000),
  })
  .strict();

function invalidConfig(details: unknown): AppError {
  return new AppError({
    code: "AI_ROUTE_CONFIG_INVALID",
    details,
    message: "The AI route configuration is invalid.",
    statusCode: 500,
  });
}

export function validateManagedSettings(
  value: unknown,
  allowedModels: readonly string[],
): AiRouteSettings {
  const result = aiRouteSettingsSchema.safeParse(value);
  if (!result.success) {
    throw invalidConfig(result.error.issues);
  }
  if (!allowedModels.includes(result.data.model)) {
    throw new AppError({
      code: "AI_MODEL_NOT_ALLOWED",
      details: { allowedModels },
      message: "The selected AI model is not allowed by runtime policy.",
      statusCode: 409,
    });
  }
  return result.data;
}

export function validateRuntimeRoute(
  route: AiRouteConfig,
  allowedModels: readonly string[],
): AiRouteConfig {
  let settings: AiRouteSettings;
  try {
    settings = validateManagedSettings(
      {
        allowJsonResponse: route.allowJsonResponse,
        enabled: true,
        maxInputCharacters: route.maxInputCharacters,
        maxMessages: route.maxMessages,
        maxOutputTokens: route.maxOutputTokens,
        model: route.model,
        provider: route.provider,
        providerOptions: route.providerOptions,
        temperature: route.temperature,
        timeoutMs: route.timeoutMs,
      },
      allowedModels,
    );
  } catch (cause) {
    throw new AppError({
      cause,
      code: "AI_ROUTE_CONFIG_INVALID",
      message: "The AI route is unavailable due to invalid configuration.",
      statusCode: 503,
    });
  }
  return {
    allowJsonResponse: settings.allowJsonResponse,
    configVersion: route.configVersion,
    maxInputCharacters: settings.maxInputCharacters,
    maxMessages: settings.maxMessages,
    maxOutputTokens: settings.maxOutputTokens,
    model: settings.model,
    provider: settings.provider,
    providerOptions: settings.providerOptions,
    task: route.task,
    temperature: settings.temperature,
    timeoutMs: settings.timeoutMs,
  };
}
