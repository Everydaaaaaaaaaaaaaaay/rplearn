import "dotenv/config";
import { buildApp } from "./app.js";
import { ConfigurationError, loadConfig } from "./config/env.js";
import { createRuntimeDependencies } from "./infrastructure/runtime-dependencies.js";
import { registerAuthRoutes } from "./modules/auth/routes.js";
import { createAuthService } from "./modules/auth/service.js";
import { createDeepSeekClient } from "./modules/ai/deepseek/client.js";
import { registerAiRoutes } from "./modules/ai/routes.js";
import { createAiService } from "./modules/ai/service.js";
import { registerAppleAuthRoutes } from "./modules/auth/apple/routes.js";
import { createAppleAuthService } from "./modules/auth/apple/service.js";
import { createAppleBillingVerifier } from "./modules/billing/apple/verifier.js";
import { registerBillingRoutes } from "./modules/billing/routes.js";
import { createBillingService } from "./modules/billing/service.js";
import { registerDomainRoutes } from "./modules/domain/routes.js";
import { createDomainService } from "./modules/domain/service.js";
import { createSyncCursorCodec } from "./modules/sync/cursor.js";
import { registerSyncRoutes } from "./modules/sync/routes.js";
import { createSyncService } from "./modules/sync/service.js";
import { registerAuditHooks } from "./modules/observability/audit.js";
import { registerAccountRoutes } from "./modules/account/routes.js";
import { createAccountService } from "./modules/account/service.js";
import { createContentCursorCodec } from "./modules/content/cursor.js";
import { registerContentRoutes } from "./modules/content/routes.js";
import { createContentService } from "./modules/content/service.js";

async function main(): Promise<void> {
  let config: ReturnType<typeof loadConfig>;

  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof ConfigurationError) {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
      return;
    }

    throw error;
  }

  const dependencies = createRuntimeDependencies(config);
  const app = await buildApp(config, {
    readinessChecks: dependencies.readinessChecks,
  });
  registerAuditHooks(app, config, dependencies.database);
  const authService = await createAuthService(config, dependencies.database);
  registerAuthRoutes(app, authService);
  registerAccountRoutes(
    app,
    authService,
    createAccountService(config, dependencies.database),
  );
  if (config.appleAuthEnabled) {
    const appleAuthService = await createAppleAuthService(
      config,
      dependencies.database,
      dependencies.redis,
      authService,
    );
    registerAppleAuthRoutes(app, appleAuthService, authService);
  }
  const billingService = createBillingService(
    dependencies.database,
    config.appleBillingEnabled ? createAppleBillingVerifier(config) : undefined,
  );
  registerBillingRoutes(app, authService, billingService, {
    appleBillingEnabled: config.appleBillingEnabled,
    enableDebugRoutes: config.nodeEnv !== "production",
  });
  const aiService = createAiService(
    config,
    dependencies.database,
    dependencies.redis,
    billingService,
    createDeepSeekClient(config),
  );
  registerAiRoutes(app, authService, aiService);
  const domainService = createDomainService(dependencies.database);
  registerDomainRoutes(app, authService, domainService, {
    enableDebugRoutes: config.nodeEnv !== "production",
  });
  const syncCursor = createSyncCursorCodec(config.authTokenHashPepper);
  const contentService = createContentService(
    dependencies.database,
    createContentCursorCodec(config.authTokenHashPepper),
    syncCursor,
  );
  registerContentRoutes(app, authService, contentService);
  const syncService = createSyncService(
    dependencies.database,
    domainService,
    syncCursor,
  );
  registerSyncRoutes(app, authService, syncService);
  let closing = false;

  dependencies.onRedisError((error) => {
    app.log.error(
      {
        errorName: error.name,
      },
      "Redis client error",
    );
  });

  app.addHook("onClose", async () => {
    await dependencies.close();
  });

  const shutdown = async (signal: NodeJS.Signals): Promise<void> => {
    if (closing) {
      return;
    }

    closing = true;
    app.log.info({ signal }, "Graceful shutdown started");

    const forceClose = setTimeout(() => {
      app.log.fatal("Graceful shutdown deadline exceeded");
      process.exitCode = 1;
    }, config.shutdownGraceMs);
    forceClose.unref();

    try {
      await app.close();
    } finally {
      clearTimeout(forceClose);
    }
  };

  process.once("SIGINT", () => {
    void shutdown("SIGINT");
  });
  process.once("SIGTERM", () => {
    void shutdown("SIGTERM");
  });

  try {
    await dependencies.start();
    await app.listen({
      host: config.host,
      port: config.port,
    });
  } catch (error) {
    app.log.fatal(
      {
        errorName: error instanceof Error ? error.name : "UnknownError",
      },
      "Server failed to start",
    );
    await app.close();
    process.exitCode = 1;
  }
}

void main().catch(() => {
  process.stderr.write("Server failed before structured logging was available.\n");
  process.exitCode = 1;
});
