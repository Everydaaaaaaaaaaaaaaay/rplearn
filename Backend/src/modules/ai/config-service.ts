import { createHash } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { validateManagedSettings } from "./config.js";
import { AiConfigRepository } from "./config-repository.js";
import type { AiCatalogService } from "./catalog-service.js";
import type { AiManagedRoute, AiRouteRevision, AiRouteSettings } from "./types.js";

type ChangeContext = Readonly<{
  changeReason: string;
  commandId: string;
  expectedVersion: number;
  operatorKeyId: string;
}>;

export type AiBulkModelChange = Readonly<{
  provider: AiRouteSettings["provider"];
  model: string;
  expectedVersions: Readonly<Record<string, number>>;
}>;

export type AiConfigService = Readonly<{
  allowedModels: readonly string[];
  providerStatus: Readonly<{
    deepseek: Readonly<{ configured: boolean }>;
    openrouter: Readonly<{ configured: boolean; usdToCny: string | null }>;
  }>;
  switchAllModels: (
    change: AiBulkModelChange,
    context: Omit<ChangeContext, "expectedVersion">,
  ) => Promise<readonly AiManagedRoute[]>;
  listRoutes: () => Promise<readonly AiManagedRoute[]>;
  revisions: (task: string, limit: number) => Promise<readonly AiRouteRevision[]>;
  rollback: (
    task: string,
    targetVersion: number,
    context: ChangeContext,
  ) => Promise<AiManagedRoute>;
  update: (
    task: string,
    settings: AiRouteSettings,
    context: ChangeContext,
  ) => Promise<AiManagedRoute>;
}>;

function requestHash(value: unknown): string {
  return createHash("sha256").update(JSON.stringify(value)).digest("hex");
}

export function createAiConfigService(
  config: RuntimeConfig,
  database: DatabaseResource,
  catalog?: AiCatalogService,
): AiConfigService {
  const repository = new AiConfigRepository(database);
  const apply = async (
    task: string,
    rawSettings: unknown,
    context: ChangeContext,
    action: Readonly<Record<string, unknown>>,
  ): Promise<AiManagedRoute> => {
    const settings = validateManagedSettings(rawSettings, {
      deepSeekAllowedModels: config.aiDeepSeekAllowedModels,
      openRouterEnabled: catalog?.configured ?? false,
    });
    if (settings.provider === "openrouter") {
      if (catalog === undefined) {
        throw new Error("OpenRouter catalog is unavailable");
      }
      await catalog.assertSelectable(settings.model, {
        requiresJson: settings.allowJsonResponse,
      });
    }
    return repository.update(
      task,
      context.expectedVersion,
      settings,
      context.commandId,
      context.operatorKeyId,
      context.changeReason,
      requestHash({
        ...action,
        changeReason: context.changeReason,
        expectedVersion: context.expectedVersion,
        operatorKeyId: context.operatorKeyId,
        settings,
        task,
      }),
    );
  };

  return {
    allowedModels: config.aiDeepSeekAllowedModels,
    providerStatus: {
      deepseek: { configured: config.deepSeekApiKey !== undefined },
      openrouter: {
        configured: catalog?.configured ?? false,
        usdToCny: catalog?.usdToCny ?? null,
      },
    },
    switchAllModels: async (change, context) => {
      if (change.provider === "deepseek" && config.deepSeekApiKey === undefined) {
        throw new AppError({
          code: "AI_PROVIDER_NOT_CONFIGURED",
          message: "DeepSeek is not configured for this deployment.",
          statusCode: 409,
        });
      }
      const routes = await repository.listRoutes();
      const expectedTasks = Object.keys(change.expectedVersions).sort();
      if (
        JSON.stringify(expectedTasks) !==
        JSON.stringify(routes.map((route) => route.task).sort())
      ) {
        throw new AppError({
          code: "AI_ROUTE_VERSION_CONFLICT",
          message: "The task list changed. Refresh before switching all routes.",
          statusCode: 409,
        });
      }
      const changes = [];
      for (const route of routes) {
        const task = route.task;
        const expectedVersion = change.expectedVersions[task];
        if (expectedVersion === undefined)
          throw new Error("Missing expected route version");
        const settings = validateManagedSettings(
          {
            allowJsonResponse: route.allowJsonResponse,
            enabled: route.enabled,
            maxInputCharacters: route.maxInputCharacters,
            maxMessages: route.maxMessages,
            maxOutputTokens: route.maxOutputTokens,
            temperature: route.temperature,
            timeoutMs: route.timeoutMs,
            provider: change.provider,
            model: change.model,
            providerOptions:
              route.provider === change.provider
                ? route.providerOptions
                : change.provider === "openrouter"
                  ? { provider: { require_parameters: true } }
                  : { thinking: { type: "disabled" } },
          },
          {
            deepSeekAllowedModels: config.aiDeepSeekAllowedModels,
            openRouterEnabled: catalog?.configured ?? false,
          },
        );
        if (settings.provider === "openrouter") {
          if (catalog === undefined)
            throw new Error("OpenRouter catalog is unavailable");
          await catalog.assertSelectable(settings.model, {
            requiresJson: settings.allowJsonResponse,
          });
        }
        changes.push({
          task,
          expectedVersion,
          settings,
        });
      }
      return repository.updateAll(
        changes,
        context.commandId,
        context.operatorKeyId,
        context.changeReason,
        requestHash({
          action: "switch-all-models",
          provider: change.provider,
          model: change.model,
          expectedVersions: expectedTasks.map((task) => [
            task,
            change.expectedVersions[task],
          ]),
          changeReason: context.changeReason,
          operatorKeyId: context.operatorKeyId,
        }),
      );
    },
    listRoutes: () => repository.listRoutes(),
    revisions: (task, limit) => repository.revisions(task, limit),
    rollback: async (task, targetVersion, context) => {
      const settings = await repository.settingsAtVersion(task, targetVersion);
      return apply(task, settings, context, {
        action: "rollback",
        targetVersion,
      });
    },
    update: (task, settings, context) =>
      apply(task, settings, context, { action: "update" }),
  };
}
