import "dotenv/config";
import { buildApp } from "./app.js";
import { ConfigurationError, loadConfig } from "./config/env.js";

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

  const app = await buildApp(config);
  let closing = false;

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

  await app.listen({
    host: config.host,
    port: config.port,
  });
}

void main();
