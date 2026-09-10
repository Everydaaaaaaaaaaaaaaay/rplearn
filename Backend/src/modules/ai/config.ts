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

const openRouterProviderOptionsSchema = z
  .object({
    frequency_penalty: z.number().min(-2).max(2).optional(),
    presence_penalty: z.number().min(-2).max(2).optional(),
    provider: z
      .object({
        allow_fallbacks: z.boolean().optional(),
        data_collection: z.enum(["allow", "deny"]).optional(),
        ignore: z.array(z.string().trim().min(1).max(128)).max(32).optional(),
        only: z.array(z.string().trim().min(1).max(128)).max(32).optional(),
        order: z.array(z.string().trim().min(1).max(128)).max(32).optional(),
        require_parameters: z.boolean().optional(),
        sort: z.enum(["price", "latency", "throughput"]).optional(),
      })
      .strict()
      .optional(),
    reasoning: z
      .object({
        enabled: z.boolean().optional(),
        effort: z.enum(["minimal", "low", "medium", "high"]).optional(),
        max_tokens: z.number().int().min(1).max(64_000).optional(),
      })
      .strict()
      .optional(),
    repetition_penalty: z.number().min(0).max(2).optional(),
    seed: z.number().int().optional(),
    stop: stopSchema.nullable().optional(),
    top_k: z.number().int().min(0).max(500).optional(),
    top_p: z.number().min(0).max(1).optional(),
  })
  .strict();

const commonRouteSettings = {
  allowJsonResponse: z.boolean(),
  enabled: z.boolean(),
  maxInputCharacters: z.number().int().min(1).max(500_000),
  maxMessages: z.number().int().min(1).max(100),
  maxOutputTokens: z.number().int().min(1).max(384_000),
  temperature: z.number().min(0).max(2).nullable(),
  timeoutMs: z.number().int().min(1_000).max(120_000),
};

export const aiRouteSettingsSchema = z
  .discriminatedUnion("provider", [
    z
      .object({
        ...commonRouteSettings,
        model: z.string().regex(/^[a-zA-Z0-9][a-zA-Z0-9._-]{1,127}$/),
        provider: z.literal("deepseek"),
        providerOptions: deepSeekProviderOptionsSchema,
      })
      .strict(),
    z
      .object({
        ...commonRouteSettings,
        model: z.string().regex(/^[a-zA-Z0-9][a-zA-Z0-9._:/-]{1,191}$/),
        provider: z.literal("openrouter"),
        providerOptions: openRouterProviderOptionsSchema,
      })
      .strict(),
  ])
  .superRefine((settings, context) => {
    if (
      settings.provider === "openrouter" &&
      settings.allowJsonResponse &&
      settings.providerOptions.provider?.require_parameters !== true
    ) {
      context.addIssue({
        code: "custom",
        message:
          "OpenRouter JSON routes must require providers to support every requested parameter.",
        path: ["providerOptions", "provider", "require_parameters"],
      });
    }
  });

export type AiModelPolicy = Readonly<{
  deepSeekAllowedModels: readonly string[];
  openRouterEnabled: boolean;
}>;

function normalizedPolicy(policy: readonly string[] | AiModelPolicy): AiModelPolicy {
  return "deepSeekAllowedModels" in policy
    ? policy
    : { deepSeekAllowedModels: policy, openRouterEnabled: false };
}

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
  rawPolicy: readonly string[] | AiModelPolicy,
): AiRouteSettings {
  const policy = normalizedPolicy(rawPolicy);
  const result = aiRouteSettingsSchema.safeParse(value);
  if (!result.success) {
    throw invalidConfig(result.error.issues);
  }
  if (
    result.data.provider === "deepseek" &&
    !policy.deepSeekAllowedModels.includes(result.data.model)
  ) {
    throw new AppError({
      code: "AI_MODEL_NOT_ALLOWED",
      details: { allowedModels: policy.deepSeekAllowedModels },
      message: "The selected AI model is not allowed by runtime policy.",
      statusCode: 409,
    });
  }
  if (result.data.provider === "openrouter" && !policy.openRouterEnabled) {
    throw new AppError({
      code: "AI_PROVIDER_NOT_CONFIGURED",
      message: "OpenRouter is not configured for this deployment.",
      statusCode: 409,
    });
  }
  return result.data;
}

export function validateRuntimeRoute(
  route: AiRouteConfig,
  policy: readonly string[] | AiModelPolicy,
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
      policy,
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
