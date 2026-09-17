import type { TransactionSql } from "postgres";
import { v5 as uuidv5 } from "uuid";
import { isDeepStrictEqual } from "node:util";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { newEntityId } from "../../shared/id.js";
import type { AiManagedRoute, AiRouteRevision, AiRouteSettings } from "./types.js";

type ManagedRouteRow = Readonly<{
  allow_json_response: boolean;
  config_version: number;
  enabled: boolean;
  max_input_characters: number;
  max_messages: number;
  max_output_tokens: number;
  model: string;
  provider: AiRouteSettings["provider"];
  provider_options_text: string;
  task: string;
  temperature: number | null;
  timeout_ms: number;
  updated_at: string;
}>;

type RevisionRow = Readonly<{
  changed_at: string;
  change_reason: string;
  config_version: number;
  new_config_text: string;
  operator_key_id: string;
}>;

function settings(row: ManagedRouteRow): AiRouteSettings {
  return {
    allowJsonResponse: row.allow_json_response,
    enabled: row.enabled,
    maxInputCharacters: row.max_input_characters,
    maxMessages: row.max_messages,
    maxOutputTokens: row.max_output_tokens,
    model: row.model,
    provider: row.provider,
    providerOptions: JSON.parse(row.provider_options_text) as Readonly<
      Record<string, unknown>
    >,
    temperature: row.temperature,
    timeoutMs: row.timeout_ms,
  };
}

function managed(row: ManagedRouteRow): AiManagedRoute {
  return {
    ...settings(row),
    configVersion: row.config_version,
    task: row.task,
    updatedAt: new Date(row.updated_at).toISOString(),
  };
}

function notFound(): AppError {
  return new AppError({
    code: "AI_ROUTE_NOT_FOUND",
    message: "The AI route does not exist.",
    statusCode: 404,
  });
}

export class AiConfigRepository {
  constructor(private readonly database: DatabaseResource) {}

  // Automatic speech feedback is retired; chat sentence translation is served
  // by the cloud route again, so only the retired task stays out of management.
  // Retain historical records for the retired route.
  async listRoutes(): Promise<readonly AiManagedRoute[]> {
    const rows = await this.database.sql<ManagedRouteRow[]>`
      select
        task,
        provider,
        model,
        max_messages,
        max_input_characters,
        max_output_tokens,
        temperature,
        allow_json_response,
        timeout_ms,
        provider_options::text as provider_options_text,
        enabled,
        config_version,
        updated_at
      from app.ai_routes
      where task <> 'speech_feedback'
      order by task
    `;
    return rows.map(managed);
  }

  async revisions(task: string, limit: number): Promise<readonly AiRouteRevision[]> {
    const rows = await this.database.sql<RevisionRow[]>`
      select
        config_version,
        operator_key_id,
        change_reason,
        new_config::text as new_config_text,
        changed_at
      from app.ai_route_revisions
      where task = ${task}
      order by config_version desc
      limit ${limit}
    `;
    return rows.map((row) => ({
      changedAt: new Date(row.changed_at).toISOString(),
      changeReason: row.change_reason,
      configVersion: row.config_version,
      operatorKeyId: row.operator_key_id,
      settings: JSON.parse(row.new_config_text) as AiRouteSettings,
    }));
  }

  async settingsAtVersion(
    task: string,
    configVersion: number,
  ): Promise<AiRouteSettings> {
    const [row] = await this.database.sql<{ new_config_text: string }[]>`
      select new_config::text as new_config_text
      from app.ai_route_revisions
      where task = ${task}
        and config_version = ${configVersion}
    `;
    if (row === undefined) {
      throw new AppError({
        code: "AI_ROUTE_REVISION_NOT_FOUND",
        message: "The requested AI route revision does not exist.",
        statusCode: 404,
      });
    }
    return JSON.parse(row.new_config_text) as AiRouteSettings;
  }

  async update(
    task: string,
    expectedVersion: number,
    nextSettings: AiRouteSettings,
    commandId: string,
    operatorKeyId: string,
    changeReason: string,
    requestHash: string,
  ): Promise<AiManagedRoute> {
    return this.database.sql.begin((sql) =>
      this.updateInTransaction(
        sql,
        task,
        expectedVersion,
        nextSettings,
        commandId,
        operatorKeyId,
        changeReason,
        requestHash,
      ),
    );
  }

  async updateAll(
    changes: readonly Readonly<{
      task: string;
      expectedVersion: number;
      settings: AiRouteSettings;
    }>[],
    commandId: string,
    operatorKeyId: string,
    changeReason: string,
    requestHash: string,
  ): Promise<readonly AiManagedRoute[]> {
    return this.database.sql.begin(async (sql) => {
      // Same command lock as single-route writes; ordered route locks prevent deadlocks.
      await sql`select pg_advisory_xact_lock(hashtextextended(${`ai-route-command:${commandId}`}, 0))`;
      const ordered = [...changes].sort((a, b) => a.task.localeCompare(b.task));
      for (const change of ordered) {
        await sql`select pg_advisory_xact_lock(hashtextextended(${`ai-route:${change.task}`}, 0))`;
      }
      const tasks = await sql<
        { task: string }[]
      >`select task from app.ai_routes where task <> 'speech_feedback' order by task`;
      if (
        !isDeepStrictEqual(
          tasks.map((row) => row.task).sort(),
          ordered.map((row) => row.task).sort(),
        )
      ) {
        throw new AppError({
          code: "AI_ROUTE_VERSION_CONFLICT",
          message: "The task list changed. Refresh before switching all routes.",
          statusCode: 409,
        });
      }
      const routes: AiManagedRoute[] = [];
      for (const [index, change] of ordered.entries()) {
        routes.push(
          await this.updateInTransaction(
            sql,
            change.task,
            change.expectedVersion,
            change.settings,
            index === 0 ? commandId : uuidv5(change.task, commandId),
            operatorKeyId,
            changeReason,
            requestHash,
            true,
            false,
          ),
        );
      }
      return routes;
    });
  }

  private async updateInTransaction(
    sql: TransactionSql,
    task: string,
    expectedVersion: number,
    nextSettings: AiRouteSettings,
    commandId: string,
    operatorKeyId: string,
    changeReason: string,
    requestHash: string,
    allowUnchanged = false,
    acquireLocks = true,
  ): Promise<AiManagedRoute> {
    if (acquireLocks) {
      await sql`
        select pg_advisory_xact_lock(
          hashtextextended(${`ai-route-command:${commandId}`}, 0)
        )
      `;
      await sql`
        select pg_advisory_xact_lock(hashtextextended(${`ai-route:${task}`}, 0))
      `;
    }
    const [existing] = await sql<
      {
        changed_at: string;
        config_version: number;
        new_config_text: string;
        request_hash: string;
        task: string;
      }[]
    >`
        select
          task,
          config_version,
          request_hash,
          new_config::text as new_config_text,
          changed_at
        from app.ai_route_revisions
        where command_id = ${commandId}
      `;
    if (existing !== undefined) {
      if (existing.request_hash !== requestHash || existing.task !== task) {
        throw new AppError({
          code: "IDEMPOTENCY_KEY_CONFLICT",
          message:
            "This idempotency key was already used for another configuration change.",
          statusCode: 409,
        });
      }
      return {
        ...(JSON.parse(existing.new_config_text) as AiRouteSettings),
        configVersion: existing.config_version,
        task,
        updatedAt: new Date(existing.changed_at).toISOString(),
      };
    }

    const [current] = await sql<ManagedRouteRow[]>`
        select
          task,
          provider,
          model,
          max_messages,
          max_input_characters,
          max_output_tokens,
          temperature,
          allow_json_response,
          timeout_ms,
          provider_options::text as provider_options_text,
          enabled,
          config_version,
          updated_at
        from app.ai_routes
        where task = ${task}
        for update
      `;
    if (current === undefined) {
      throw notFound();
    }
    if (current.config_version !== expectedVersion) {
      throw new AppError({
        code: "AI_ROUTE_VERSION_CONFLICT",
        details: { currentVersion: current.config_version },
        message: "The AI route was changed by another operator.",
        statusCode: 409,
      });
    }
    const previousSettings = settings(current);
    if (!allowUnchanged && isDeepStrictEqual(previousSettings, nextSettings)) {
      throw new AppError({
        code: "AI_ROUTE_CONFIG_UNCHANGED",
        message: "The requested AI route configuration is unchanged.",
        statusCode: 409,
      });
    }
    const nextVersion = current.config_version + 1;
    const [updated] = await sql<ManagedRouteRow[]>`
        update app.ai_routes
        set provider = ${nextSettings.provider}::app.ai_provider,
            model = ${nextSettings.model},
            max_messages = ${nextSettings.maxMessages},
            max_input_characters = ${nextSettings.maxInputCharacters},
            max_output_tokens = ${nextSettings.maxOutputTokens},
            temperature = ${nextSettings.temperature},
            allow_json_response = ${nextSettings.allowJsonResponse},
            timeout_ms = ${nextSettings.timeoutMs},
            provider_options =
              ${JSON.stringify(nextSettings.providerOptions)}::jsonb,
            enabled = ${nextSettings.enabled},
            config_version = ${nextVersion},
            updated_at = now()
        where task = ${task}
        returning
          task,
          provider,
          model,
          max_messages,
          max_input_characters,
          max_output_tokens,
          temperature,
          allow_json_response,
          timeout_ms,
          provider_options::text as provider_options_text,
          enabled,
          config_version,
          updated_at
      `;
    if (updated === undefined) {
      throw notFound();
    }
    await sql`
        insert into app.ai_route_revisions (
          id,
          task,
          config_version,
          command_id,
          request_hash,
          operator_key_id,
          change_reason,
          previous_config,
          new_config
        )
        values (
          ${newEntityId()},
          ${task},
          ${nextVersion},
          ${commandId},
          ${requestHash},
          ${operatorKeyId},
          ${changeReason},
          ${JSON.stringify(previousSettings)}::jsonb,
          ${JSON.stringify(nextSettings)}::jsonb
        )
      `;
    return managed(updated);
  }
}
