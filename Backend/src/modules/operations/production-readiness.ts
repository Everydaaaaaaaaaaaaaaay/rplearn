import { createPrivateKey } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import { assertMigrationsCurrent } from "../../db/migrate.js";
import type { RedisResource } from "../../infrastructure/redis/client.js";
import type { DeepSeekOperationalClient } from "../ai/deepseek/client.js";
import type { OpenRouterClient } from "../ai/openrouter/client.js";
import { createAppleClientSecretFactory } from "../auth/apple/client-secret.js";
import type { SmtpAuthNotifier } from "../auth/notifier.js";
import { createAppleBillingStatusClient } from "../billing/apple/server-api-client.js";
import { createAppleBillingVerifier } from "../billing/apple/verifier.js";
import type { MediaObjectStore } from "../media/object-store.js";

export type ProductionReadinessCheckResult =
  | Readonly<{
      durationMs: number;
      name: string;
      status: "passed";
    }>
  | Readonly<{
      code: string;
      durationMs: number;
      name: string;
      status: "failed";
    }>;

export type ProductionReadinessReport = Readonly<{
  checkedAt: string;
  checks: readonly ProductionReadinessCheckResult[];
  passed: boolean;
}>;

export type ProductionReadinessCheck = Readonly<{
  check: () => Promise<void>;
  failureCode: string;
  name: string;
}>;

export type RuntimeDatabaseAuthority = Readonly<{
  canCreateDatabase: boolean;
  canCreateSchema: boolean;
  canUseAppSchema: boolean;
  hasTableDml: boolean;
  roleBypassesRls: boolean;
  roleCanCreateDatabase: boolean;
  roleCanCreateRole: boolean;
  roleCanLogin: boolean;
  roleCanReplicate: boolean;
  roleIsSuperuser: boolean;
  tableCount: number;
}>;

export class ProductionReadinessError extends Error {
  readonly code: string;

  constructor(code: string) {
    super(code);
    this.name = "ProductionReadinessError";
    this.code = code;
  }
}

function failureCode(error: unknown, fallback: string): string {
  return error instanceof ProductionReadinessError ? error.code : fallback;
}

async function runCheck(
  definition: ProductionReadinessCheck,
  timeoutMs: number,
): Promise<ProductionReadinessCheckResult> {
  const startedAt = performance.now();
  let timeout: NodeJS.Timeout | undefined;
  try {
    await Promise.race([
      definition.check(),
      new Promise<never>((_resolve, reject) => {
        timeout = setTimeout(
          () => reject(new ProductionReadinessError("CHECK_TIMEOUT")),
          timeoutMs,
        );
      }),
    ]);
    return {
      durationMs: Math.round(performance.now() - startedAt),
      name: definition.name,
      status: "passed",
    };
  } catch (error) {
    return {
      code: failureCode(error, definition.failureCode),
      durationMs: Math.round(performance.now() - startedAt),
      name: definition.name,
      status: "failed",
    };
  } finally {
    clearTimeout(timeout);
  }
}

export async function runProductionReadinessChecks(
  definitions: readonly ProductionReadinessCheck[],
  timeoutMs: number,
  now: () => Date = () => new Date(),
): Promise<ProductionReadinessReport> {
  const checks = await Promise.all(
    definitions.map((definition) => runCheck(definition, timeoutMs)),
  );
  return {
    checkedAt: now().toISOString(),
    checks,
    passed: checks.every((check) => check.status === "passed"),
  };
}

export function assertRuntimeDatabaseAuthority(
  authority: RuntimeDatabaseAuthority,
): void {
  if (
    authority.roleIsSuperuser ||
    authority.roleCanCreateDatabase ||
    authority.roleCanCreateRole ||
    authority.roleCanReplicate ||
    authority.roleBypassesRls ||
    authority.canCreateDatabase ||
    authority.canCreateSchema
  ) {
    throw new ProductionReadinessError("DATABASE_ROLE_OVER_PRIVILEGED");
  }
  if (
    !authority.roleCanLogin ||
    !authority.canUseAppSchema ||
    authority.tableCount === 0 ||
    !authority.hasTableDml
  ) {
    throw new ProductionReadinessError("DATABASE_ROLE_UNDER_PRIVILEGED");
  }
}

export async function assertRuntimeDatabaseRole(
  resource: DatabaseResource,
): Promise<void> {
  const [authority] = await resource.sql<RuntimeDatabaseAuthority[]>`
    select
      role.rolcanlogin as "roleCanLogin",
      role.rolsuper as "roleIsSuperuser",
      role.rolcreatedb as "roleCanCreateDatabase",
      role.rolcreaterole as "roleCanCreateRole",
      role.rolreplication as "roleCanReplicate",
      role.rolbypassrls as "roleBypassesRls",
      has_database_privilege(current_user, current_database(), 'CREATE')
        as "canCreateDatabase",
      has_schema_privilege(current_user, 'app', 'CREATE') as "canCreateSchema",
      has_schema_privilege(current_user, 'app', 'USAGE') as "canUseAppSchema",
      (
        select count(*)::integer
        from pg_tables
        where schemaname = 'app'
      ) as "tableCount",
      (
        select coalesce(
          bool_and(
            has_table_privilege(
              current_user,
              format('%I.%I', schemaname, tablename),
              'SELECT'
            )
            and has_table_privilege(
              current_user,
              format('%I.%I', schemaname, tablename),
              'INSERT'
            )
            and has_table_privilege(
              current_user,
              format('%I.%I', schemaname, tablename),
              'UPDATE'
            )
            and has_table_privilege(
              current_user,
              format('%I.%I', schemaname, tablename),
              'DELETE'
            )
          ),
          false
        )
        from pg_tables
        where schemaname = 'app'
      ) as "hasTableDml"
    from pg_roles as role
    where role.rolname = current_user
  `;
  if (authority === undefined) {
    throw new ProductionReadinessError("DATABASE_ROLE_UNAVAILABLE");
  }
  assertRuntimeDatabaseAuthority(authority);
}

export function assertAllowedModelsAvailable(
  allowedModels: readonly string[],
  availableModels: readonly string[],
): void {
  const catalog = new Set(availableModels);
  if (allowedModels.some((model) => !catalog.has(model))) {
    throw new ProductionReadinessError("AI_MODEL_UNAVAILABLE");
  }
}

export function assertOpenRouterModelsAvailable(
  activeModels: readonly string[],
  localModels: readonly string[],
  upstreamModels: readonly string[],
  configured: boolean,
): void {
  if (activeModels.length === 0) return;
  if (!configured) {
    throw new ProductionReadinessError("OPENROUTER_NOT_CONFIGURED");
  }
  const local = new Set(localModels);
  const upstream = new Set(upstreamModels);
  if (activeModels.some((model) => !local.has(model) || !upstream.has(model))) {
    throw new ProductionReadinessError("OPENROUTER_MODEL_UNAVAILABLE");
  }
}

async function assertActiveOpenRouterRoutes(
  database: DatabaseResource,
  openRouter: OpenRouterClient,
): Promise<void> {
  const active = await database.sql<{ model: string }[]>`
    select distinct model
    from app.ai_routes
    where enabled=true and provider='openrouter'
  `;
  if (active.length === 0) return;
  if (!openRouter.configured) {
    assertOpenRouterModelsAvailable(
      active.map((route) => route.model),
      [],
      [],
      false,
    );
    return;
  }
  const [local, upstream] = await Promise.all([
    database.sql<{ model: string }[]>`
      select model
      from app.ai_model_catalog
      where provider='openrouter' and available=true
    `,
    openRouter.models(),
  ]);
  assertOpenRouterModelsAvailable(
    active.map((route) => route.model),
    local.map((model) => model.model),
    upstream.map((model) => model.id),
    true,
  );
}

async function assertAppleConfiguration(config: RuntimeConfig): Promise<void> {
  if (!config.appleBillingEnabled) {
    throw new ProductionReadinessError("APPLE_BILLING_DISABLED");
  }
  const billingPrivateKey = config.appleBillingPrivateKeyBase64;
  if (billingPrivateKey === undefined) {
    throw new ProductionReadinessError("APPLE_BILLING_CONFIGURATION_INVALID");
  }
  const key = createPrivateKey(
    Buffer.from(billingPrivateKey, "base64").toString("utf8"),
  );
  if (key.asymmetricKeyType !== "ec") {
    throw new ProductionReadinessError("APPLE_BILLING_CONFIGURATION_INVALID");
  }
  const verifier = createAppleBillingVerifier(config);
  createAppleBillingStatusClient(config, verifier);

  if (config.appleAuthEnabled) {
    const clientId = config.appleClientIds[0];
    if (clientId === undefined) {
      throw new ProductionReadinessError("APPLE_AUTH_CONFIGURATION_INVALID");
    }
    const createClientSecret = await createAppleClientSecretFactory(config);
    await createClientSecret(clientId);
  }
}

export function createProductionReadinessChecks(
  config: RuntimeConfig,
  dependencies: Readonly<{
    ai: DeepSeekOperationalClient;
    database: DatabaseResource;
    media: MediaObjectStore;
    openRouter: OpenRouterClient;
    redis: RedisResource;
    smtp: SmtpAuthNotifier;
  }>,
): readonly ProductionReadinessCheck[] {
  return [
    {
      check: dependencies.database.ping,
      failureCode: "DATABASE_UNAVAILABLE",
      name: "database_connectivity",
    },
    {
      check: () => assertMigrationsCurrent(dependencies.database),
      failureCode: "DATABASE_MIGRATIONS_NOT_CURRENT",
      name: "database_migrations",
    },
    {
      check: () => assertRuntimeDatabaseRole(dependencies.database),
      failureCode: "DATABASE_ROLE_INVALID",
      name: "database_runtime_role",
    },
    {
      check: async () => {
        await dependencies.redis.connect();
        await dependencies.redis.ping();
      },
      failureCode: "REDIS_UNAVAILABLE",
      name: "redis_connectivity",
    },
    {
      check: dependencies.media.ping,
      failureCode: "OBJECT_STORAGE_UNAVAILABLE",
      name: "object_storage_connectivity",
    },
    {
      check: dependencies.smtp.verify,
      failureCode: "SMTP_UNAVAILABLE",
      name: "smtp_connectivity",
    },
    {
      check: async () => {
        assertAllowedModelsAvailable(
          config.aiDeepSeekAllowedModels,
          await dependencies.ai.availableModels(),
        );
      },
      failureCode: "AI_PROVIDER_UNAVAILABLE",
      name: "ai_provider_models",
    },
    {
      check: () =>
        assertActiveOpenRouterRoutes(dependencies.database, dependencies.openRouter),
      failureCode: "OPENROUTER_PROVIDER_UNAVAILABLE",
      name: "openrouter_active_models",
    },
    {
      check: () => assertAppleConfiguration(config),
      failureCode: "APPLE_CONFIGURATION_INVALID",
      name: "apple_commercial_services",
    },
  ];
}

export function productionReadinessFailureReport(
  code: string,
  now: () => Date = () => new Date(),
): ProductionReadinessReport {
  return {
    checkedAt: now().toISOString(),
    checks: [
      {
        code,
        durationMs: 0,
        name: "configuration",
        status: "failed",
      },
    ],
    passed: false,
  };
}
