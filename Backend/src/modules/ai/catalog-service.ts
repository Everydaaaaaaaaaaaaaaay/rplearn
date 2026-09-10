import type { RuntimeConfig } from "../../config/env.js";
import { AppError } from "../../shared/errors.js";
import { openRouterCreditPrice, type CreditPrice } from "../access/credit-pricing.js";
import type { AiCatalogModel, AiCatalogRepository } from "./catalog-repository.js";
import type { OpenRouterClient } from "./openrouter/client.js";

export type AiCatalogService = Readonly<{
  assertSelectable: (
    model: string,
    options: Readonly<{ requiresJson: boolean }>,
  ) => Promise<void>;
  configured: boolean;
  listOpenRouter: () => Promise<readonly AiCatalogModel[]>;
  refreshOpenRouter: () => Promise<readonly AiCatalogModel[]>;
  resolveCreditPrice: (
    provider: string,
    model: string,
    at: Date,
  ) => Promise<CreditPrice>;
  usdToCny: string | null;
}>;

function nonnegative(value: string): boolean {
  return /^\d+(?:\.\d+)?$/.test(value);
}

function includesText(value: unknown): boolean {
  return Array.isArray(value) && value.some((item) => item === "text");
}

function supportsText(
  model: Readonly<{ architecture: Readonly<Record<string, unknown>> }>,
): boolean {
  const inputs = model.architecture.input_modalities;
  const outputs = model.architecture.output_modalities;
  return (
    (inputs === undefined || includesText(inputs)) &&
    (outputs === undefined || includesText(outputs))
  );
}

export function createAiCatalogService(
  config: RuntimeConfig,
  repository: AiCatalogRepository,
  openRouter: OpenRouterClient,
): AiCatalogService {
  const listOpenRouter = () => repository.listOpenRouter();
  return {
    assertSelectable: async (model, options) => {
      if (!openRouter.configured || config.openRouterUsdToCny === undefined) {
        throw new AppError({
          code: "AI_PROVIDER_NOT_CONFIGURED",
          message:
            "OpenRouter credentials and its USD/CNY settlement rate are required.",
          statusCode: 409,
        });
      }
      const entry = await repository.openRouterModel(model);
      if (!entry?.available) {
        throw new AppError({
          code: "AI_MODEL_NOT_ALLOWED",
          message: "Refresh the OpenRouter catalog and select an available model.",
          statusCode: 409,
        });
      }
      if (
        options.requiresJson &&
        !entry.supportedParameters.some(
          (parameter) =>
            parameter === "response_format" || parameter === "structured_outputs",
        )
      ) {
        throw new AppError({
          code: "AI_MODEL_CAPABILITY_MISSING",
          message: "This model does not advertise structured JSON output support.",
          statusCode: 409,
        });
      }
    },
    configured: openRouter.configured && config.openRouterUsdToCny !== undefined,
    listOpenRouter,
    refreshOpenRouter: async () => {
      const models = (await openRouter.models()).filter(
        (model) =>
          supportsText(model) &&
          nonnegative(model.promptPriceUsd) &&
          nonnegative(model.completionPriceUsd) &&
          (model.cachedInputPriceUsd === null ||
            nonnegative(model.cachedInputPriceUsd)),
      );
      if (models.length === 0) {
        throw new AppError({
          code: "AI_MODEL_CATALOG_EMPTY",
          message: "OpenRouter returned no billable text models.",
          statusCode: 502,
        });
      }
      await repository.replaceOpenRouter(models);
      return listOpenRouter();
    },
    resolveCreditPrice: async (provider, model, at) => {
      if (provider !== "openrouter" || config.openRouterUsdToCny === undefined) {
        throw new AppError({
          code: "AI_PRICE_UNAVAILABLE",
          message: "The selected provider does not have a verified credit price.",
          statusCode: 503,
        });
      }
      const entry = await repository.openRouterModel(model);
      if (!entry?.available) {
        throw new AppError({
          code: "AI_PRICE_UNAVAILABLE",
          message:
            "Refresh the OpenRouter model catalog and select an available model before using this route.",
          statusCode: 503,
        });
      }
      return openRouterCreditPrice(
        model,
        {
          cachedInputPriceUsd: entry.cachedInputPriceUsd,
          completionPriceUsd: entry.completionPriceUsd,
          observedAt: entry.refreshedAt,
          promptPriceUsd: entry.promptPriceUsd,
        },
        config.openRouterUsdToCny,
        at,
      );
    },
    usdToCny: config.openRouterUsdToCny ?? null,
  };
}
