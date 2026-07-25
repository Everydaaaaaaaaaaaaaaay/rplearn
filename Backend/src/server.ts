import "dotenv/config";
import { buildApp } from "./app.js";
import { ConfigurationError, loadConfig } from "./config/env.js";
import { createRuntimeDependencies } from "./infrastructure/runtime-dependencies.js";
import { registerAuthRoutes } from "./modules/auth/routes.js";
import { createAuthService } from "./modules/auth/service.js";

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
  const authService = await createAuthService(config, dependencies.database, {
    onNotificationError: (error) => {
      app.log.error(
        {
          errorName: error.name,
        },
        "Authentication notification delivery failed",
      );
    },
  });
  registerAuthRoutes(app, authService);
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
