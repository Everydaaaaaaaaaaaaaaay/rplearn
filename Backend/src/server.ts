import { createAccessService } from "./modules/access/service.js";
import { registerAccessRoutes } from "./modules/access/routes.js";
import "dotenv/config";
import { shutdownTelemetry } from "./instrumentation.js";
import { buildApp } from "./app.js";
import { ConfigurationError, loadConfig } from "./config/env.js";
import { createRuntimeDependencies } from "./infrastructure/runtime-dependencies.js";
import { registerAuthRoutes } from "./modules/auth/routes.js";
import { createAuthService } from "./modules/auth/service.js";
import { createGuestService } from "./modules/auth/guest-service.js";
import { registerGuestRoutes } from "./modules/auth/guest-routes.js";
import { createGuestClaim } from "./infrastructure/guest-claim.js";
import { createDeepSeekClient } from "./modules/ai/deepseek/client.js";
import { registerAiRoutes } from "./modules/ai/routes.js";
import { createAiService } from "./modules/ai/service.js";
import { registerAiAdminRoutes } from "./modules/ai/admin-routes.js";
import { createAiConfigService } from "./modules/ai/config-service.js";
import { createAdminAuthenticator } from "./modules/admin/http.js";
import { registerAppleAuthRoutes } from "./modules/auth/apple/routes.js";
import { createAppleAuthService } from "./modules/auth/apple/service.js";
import { createCredentialSealer } from "./modules/auth/apple/credential-crypto.js";
import { createAppleTokenRevoker } from "./modules/auth/apple/token-revoker.js";
import { createAppleBillingVerifier } from "./modules/billing/apple/verifier.js";
import { registerBillingRoutes } from "./modules/billing/routes.js";
import { createBillingService } from "./modules/billing/service.js";
import { createAppleBillingStatusClient } from "./modules/billing/apple/server-api-client.js";
import { registerDomainRoutes } from "./modules/domain/routes.js";
import { createDomainService } from "./modules/domain/service.js";
import { createSyncCursorCodec } from "./modules/sync/cursor.js";
import { registerSyncRoutes } from "./modules/sync/routes.js";
import { createSyncService } from "./modules/sync/service.js";
import { registerAuditHooks } from "./modules/observability/audit.js";
import { createDatabaseMetricsSource } from "./modules/observability/database-metrics.js";
import { registerAccountRoutes } from "./modules/account/routes.js";
import { createAccountService } from "./modules/account/service.js";
import { createContentCursorCodec } from "./modules/content/cursor.js";
import { registerContentRoutes } from "./modules/content/routes.js";
import { createContentService } from "./modules/content/service.js";
import { registerHttpAbuseProtection } from "./modules/abuse/http-limiter.js";
import { createMediaObjectStore } from "./modules/media/object-store.js";
import { registerMediaRoutes } from "./modules/media/routes.js";
import { createMediaService } from "./modules/media/service.js";
import { registerNpcRoutes } from "./modules/npc/routes.js";
import { createNpcService } from "./modules/npc/service.js";
import { registerDictionaryTranslationRoutes } from "./modules/dictionary-translation/routes.js";
import { registerDictionaryTranslationAdminRoutes } from "./modules/dictionary-translation/admin-routes.js";
import { createDictionaryTranslationService } from "./modules/dictionary-translation/service.js";

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
  const mediaObjectStore = config.mediaStorageEnabled
    ? createMediaObjectStore(config)
    : undefined;
  const app = await buildApp(config, {
    operationalMetricsSource: createDatabaseMetricsSource(dependencies.database),
    readinessChecks: [
      ...dependencies.readinessChecks,
      ...(mediaObjectStore === undefined
        ? []
        : [{ check: mediaObjectStore.ping, name: "object_storage" }]),
    ],
  });
  registerHttpAbuseProtection(app, config, dependencies.redis);
  registerAuditHooks(app, config, dependencies.database);
  const authService = await createAuthService(config, dependencies.database);
  registerAuthRoutes(app, authService);
  registerAccessRoutes(app, authService, createAccessService(dependencies.database));
  registerGuestRoutes(
    app,
    authService,
    createGuestService(config, dependencies.database, authService),
    createGuestClaim(dependencies.database, config.authTokenHashPepper),
  );
  registerAccountRoutes(
    app,
    authService,
    createAccountService(
      config,
      dependencies.database,
      config.appleAuthEnabled
        ? {
            appleTokenRevoker: await createAppleTokenRevoker(config),
            credentialSealer: createCredentialSealer(config),
          }
        : {},
    ),
  );
  if (config.appleAuthEnabled) {
    const appleAuthService = await createAppleAuthService(
      config,
      dependencies.database,
      dependencies.redis,
      authService,
      {
        onVerificationFailure: (failure) => {
          app.log.warn({ appleVerification: failure }, "Apple authentication failed");
        },
      },
    );
    registerAppleAuthRoutes(app, appleAuthService, authService);
  }
  const appleBillingVerifier = config.appleBillingEnabled
    ? createAppleBillingVerifier(config)
    : undefined;
  const billingService = createBillingService(
    dependencies.database,
    appleBillingVerifier,
    appleBillingVerifier === undefined
      ? undefined
      : createAppleBillingStatusClient(config, appleBillingVerifier),
    {
      activeHours: config.appleBillingReconcileActiveHours,
      batchSize: config.appleBillingReconcileBatchSize,
      inactiveHours: config.appleBillingReconcileInactiveHours,
      retryMinutes: config.appleBillingReconcileRetryMinutes,
    },
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
  registerAiRoutes(app, authService, aiService, {
    guestAccessEnabled: false,
  });
  const dictionaryTranslationService = createDictionaryTranslationService(
    config,
    dependencies.database,
    dependencies.redis,
    {
      resolveRuntimeModelVersion: async () => {
        const route = await aiService.routeIdentity("dictionary_example_translation");
        return `${route.model}@config-${String(route.configVersion)}`;
      },
    },
  );
  registerDictionaryTranslationRoutes(
    app,
    authService,
    dictionaryTranslationService,
    {},
  );
  if (config.adminApiEnabled) {
    const authenticateAdmin = createAdminAuthenticator(config.adminApiKeys);
    registerAiAdminRoutes(
      app,
      authenticateAdmin,
      createAiConfigService(config, dependencies.database),
    );
    registerDictionaryTranslationAdminRoutes(
      app,
      authenticateAdmin,
      dictionaryTranslationService,
    );
  }
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
  registerNpcRoutes(app, authService, createNpcService(dependencies.database));
  if (mediaObjectStore !== undefined) {
    registerMediaRoutes(
      app,
      authService,
      createMediaService(config, dependencies.database, mediaObjectStore),
    );
  }
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
      await shutdownTelemetry();
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
    await shutdownTelemetry();
    process.exitCode = 1;
  }
}

void main().catch(() => {
  process.stderr.write("Server failed before structured logging was available.\n");
  process.exitCode = 1;
});
