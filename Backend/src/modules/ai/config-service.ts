import { createHash } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import { validateManagedSettings } from "./config.js";
import { AiConfigRepository } from "./config-repository.js";
import type { AiManagedRoute, AiRouteRevision, AiRouteSettings } from "./types.js";

type ChangeContext = Readonly<{
  changeReason: string;
  commandId: string;
  expectedVersion: number;
  operatorKeyId: string;
}>;

export type AiConfigService = Readonly<{
  allowedModels: readonly string[];
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
): AiConfigService {
  const repository = new AiConfigRepository(database);
  const apply = (
    task: string,
    rawSettings: unknown,
    context: ChangeContext,
    action: Readonly<Record<string, unknown>>,
  ): Promise<AiManagedRoute> => {
    const settings = validateManagedSettings(
      rawSettings,
      config.aiDeepSeekAllowedModels,
    );
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
