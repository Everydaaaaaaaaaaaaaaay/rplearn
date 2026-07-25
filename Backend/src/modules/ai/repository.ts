import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { newEntityId } from "../../shared/id.js";
import type { AiRouteConfig, AiUsage } from "./types.js";

type RouteRow = Readonly<{
  allow_json_response: boolean;
  config_version: number;
  max_input_characters: number;
  max_messages: number;
  max_output_tokens: number;
  model: string;
  provider: AiRouteConfig["provider"];
  provider_options_text: string;
  task: string;
  temperature: number | null;
  timeout_ms: number;
}>;

export class AiRepository {
  constructor(private readonly database: DatabaseResource) {}

  async route(task: string): Promise<AiRouteConfig> {
    const [row] = await this.database.sql<RouteRow[]>`
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
        config_version
      from app.ai_routes
      where task = ${task}
        and enabled = true
    `;
    if (row === undefined) {
      throw new AppError({
        code: "AI_TASK_NOT_AVAILABLE",
        message: "The requested AI task is not available.",
        statusCode: 404,
      });
    }
    return {
      allowJsonResponse: row.allow_json_response,
      configVersion: row.config_version,
      maxInputCharacters: row.max_input_characters,
      maxMessages: row.max_messages,
      maxOutputTokens: row.max_output_tokens,
      model: row.model,
      provider: row.provider,
      providerOptions: JSON.parse(row.provider_options_text) as Readonly<
        Record<string, unknown>
      >,
      task: row.task,
      temperature: row.temperature,
      timeoutMs: row.timeout_ms,
    };
  }

  async reserve(
    userId: string,
    route: AiRouteConfig,
    dailyLimit: number,
    inputCharacters: number,
  ): Promise<Readonly<{ requestId: string; startedAt: number }>> {
    const requestId = newEntityId();
    await this.database.sql.begin(async (sql) => {
      const [usage] = await sql<{ request_count: number }[]>`
        insert into app.ai_daily_usage (
          user_id,
          usage_date,
          request_count,
          quota_limit
        )
        values (
          ${userId},
          (now() at time zone 'utc')::date,
          1,
          ${dailyLimit}
        )
        on conflict (user_id, usage_date) do update
        set request_count = app.ai_daily_usage.request_count + 1,
            quota_limit = excluded.quota_limit,
            updated_at = now()
        where app.ai_daily_usage.request_count < excluded.quota_limit
        returning request_count
      `;
      if (usage === undefined) {
        throw new AppError({
          code: "AI_DAILY_QUOTA_EXCEEDED",
          details: {
            limit: dailyLimit,
            resetTimezone: "UTC",
          },
          message: "The daily AI request quota has been reached.",
          statusCode: 429,
        });
      }
      await sql`
        insert into app.ai_requests (
          id,
          user_id,
          task,
          provider,
          model,
          config_version,
          input_characters
        )
        values (
          ${requestId},
          ${userId},
          ${route.task},
          ${route.provider}::app.ai_provider,
          ${route.model},
          ${route.configVersion},
          ${inputCharacters}
        )
      `;
    });
    return {
      requestId,
      startedAt: Date.now(),
    };
  }

  async succeed(
    userId: string,
    requestId: string,
    startedAt: number,
    usage: AiUsage,
    upstreamRequestId: string | null,
  ): Promise<void> {
    await this.database.sql.begin(async (sql) => {
      await sql`
        update app.ai_requests
        set status = 'succeeded',
            input_tokens = ${usage.inputTokens},
            output_tokens = ${usage.outputTokens},
            upstream_request_id = ${upstreamRequestId},
            latency_ms = ${Math.max(0, Date.now() - startedAt)},
            completed_at = now()
        where id = ${requestId}
          and user_id = ${userId}
          and status = 'started'
      `;
      await sql`
        update app.ai_daily_usage
        set input_tokens = input_tokens + ${usage.inputTokens},
            output_tokens = output_tokens + ${usage.outputTokens},
            updated_at = now()
        where user_id = ${userId}
          and usage_date = (now() at time zone 'utc')::date
      `;
    });
  }

  async fail(
    userId: string,
    requestId: string,
    startedAt: number,
    errorCode: string,
    cancelled: boolean,
  ): Promise<void> {
    await this.database.sql`
      update app.ai_requests
      set status = ${cancelled ? "cancelled" : "failed"}::app.ai_request_status,
          error_code = ${errorCode},
          latency_ms = ${Math.max(0, Date.now() - startedAt)},
          completed_at = now()
      where id = ${requestId}
        and user_id = ${userId}
        and status = 'started'
    `;
  }
}
