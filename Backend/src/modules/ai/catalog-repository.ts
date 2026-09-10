import type { DatabaseResource } from "../../db/client.js";
import type { OpenRouterModel } from "./openrouter/client.js";

type CatalogRow = Readonly<{
  architecture_text: string;
  available: boolean;
  cached_input_price_usd: string | null;
  completion_price_usd: string;
  context_length: number | null;
  display_name: string;
  model: string;
  prompt_price_usd: string;
  refreshed_at: string;
  supported_parameters_text: string;
}>;

export type AiCatalogModel = Readonly<{
  architecture: Readonly<Record<string, unknown>>;
  available: boolean;
  cachedInputPriceUsd: string | null;
  completionPriceUsd: string;
  contextLength: number | null;
  displayName: string;
  model: string;
  promptPriceUsd: string;
  provider: "openrouter";
  refreshedAt: string;
  supportedParameters: readonly string[];
}>;

function mapRow(row: CatalogRow): AiCatalogModel {
  return {
    architecture: JSON.parse(row.architecture_text) as Readonly<
      Record<string, unknown>
    >,
    available: row.available,
    cachedInputPriceUsd: row.cached_input_price_usd,
    completionPriceUsd: row.completion_price_usd,
    contextLength: row.context_length,
    displayName: row.display_name,
    model: row.model,
    promptPriceUsd: row.prompt_price_usd,
    provider: "openrouter",
    refreshedAt: new Date(row.refreshed_at).toISOString(),
    supportedParameters: JSON.parse(row.supported_parameters_text) as readonly string[],
  };
}

const selectColumns = `
  model,
  display_name,
  context_length,
  prompt_price_usd::text,
  completion_price_usd::text,
  cached_input_price_usd::text,
  supported_parameters::text as supported_parameters_text,
  architecture::text as architecture_text,
  available,
  refreshed_at::text
`;

export class AiCatalogRepository {
  constructor(private readonly database: DatabaseResource) {}

  async replaceOpenRouter(models: readonly OpenRouterModel[]): Promise<void> {
    const payload = models.map((model) => ({
      architecture: model.architecture,
      cachedInputPriceUsd: model.cachedInputPriceUsd,
      completionPriceUsd: model.completionPriceUsd,
      contextLength: model.contextLength,
      displayName: model.name,
      model: model.id,
      promptPriceUsd: model.promptPriceUsd,
      supportedParameters: model.supportedParameters,
    }));
    await this.database.sql.begin(async (sql) => {
      await sql`update app.ai_model_catalog set available=false where provider='openrouter'`;
      if (payload.length === 0) return;
      await sql`
        insert into app.ai_model_catalog (
          provider, model, display_name, context_length,
          prompt_price_usd, completion_price_usd, cached_input_price_usd,
          supported_parameters, architecture, available, refreshed_at
        )
        select
          'openrouter'::app.ai_provider,
          source.model,
          source."displayName",
          source."contextLength",
          source."promptPriceUsd"::numeric,
          source."completionPriceUsd"::numeric,
          source."cachedInputPriceUsd"::numeric,
          source."supportedParameters",
          source.architecture,
          true,
          now()
        from jsonb_to_recordset(${JSON.stringify(payload)}::jsonb) as source(
          model text,
          "displayName" text,
          "contextLength" integer,
          "promptPriceUsd" text,
          "completionPriceUsd" text,
          "cachedInputPriceUsd" text,
          "supportedParameters" jsonb,
          architecture jsonb
        )
        on conflict (provider, model) do update set
          display_name=excluded.display_name,
          context_length=excluded.context_length,
          prompt_price_usd=excluded.prompt_price_usd,
          completion_price_usd=excluded.completion_price_usd,
          cached_input_price_usd=excluded.cached_input_price_usd,
          supported_parameters=excluded.supported_parameters,
          architecture=excluded.architecture,
          available=true,
          refreshed_at=now()
      `;
    });
  }

  async listOpenRouter(): Promise<readonly AiCatalogModel[]> {
    const rows = await this.database.sql<CatalogRow[]>`
      select ${this.database.sql.unsafe(selectColumns)}
      from app.ai_model_catalog
      where provider='openrouter' and available=true
      order by display_name, model
    `;
    return rows.map(mapRow);
  }

  async openRouterModel(model: string): Promise<AiCatalogModel | null> {
    const rows = await this.database.sql<CatalogRow[]>`
      select ${this.database.sql.unsafe(selectColumns)}
      from app.ai_model_catalog
      where provider='openrouter' and model=${model}
      limit 1
    `;
    return rows[0] === undefined ? null : mapRow(rows[0]);
  }
}
