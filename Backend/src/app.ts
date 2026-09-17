import { registerRequestDiagnostics } from "./app/request-diagnostics.js";
import cors from "@fastify/cors";
import helmet from "@fastify/helmet";
import sensible from "@fastify/sensible";
import swagger from "@fastify/swagger";
import { randomUUID } from "node:crypto";
import Fastify, {
  type FastifyInstance,
  type FastifyServerOptions,
  LogController,
} from "fastify";
import type { RuntimeConfig } from "./config/env.js";
import { registerErrorHandling } from "./app/error-handler.js";
import { registerHealthRoutes } from "./app/health.js";
import { createLoggerOptions } from "./app/logger.js";
import type { ReadinessCheck } from "./app/readiness.js";
import {
  registerMetrics,
  type OperationalMetricsSource,
} from "./modules/observability/metrics.js";

type BuildAppOptions = Readonly<{
  logger?: FastifyServerOptions["logger"];
  operationalMetricsSource?: OperationalMetricsSource;
  readinessChecks?: readonly ReadinessCheck[];
}>;

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,64}$/;

export async function buildApp(
  config: RuntimeConfig,
  options: BuildAppOptions = {},
): Promise<FastifyInstance> {
  const app = Fastify({
    bodyLimit: config.requestBodyLimitBytes,
    connectionTimeout: config.requestTimeoutMs,
    genReqId: (request) => {
      const supplied = request.headers["x-request-id"];
      return typeof supplied === "string" && REQUEST_ID_PATTERN.test(supplied)
        ? supplied
        : randomUUID();
    },
    logController: new LogController({
      disableRequestLogging: config.nodeEnv === "test",
      requestIdLogLabel: "requestId",
    }),
    logger: options.logger ?? createLoggerOptions(config.logLevel),
    requestIdHeader: false,
    trustProxy: config.trustProxy,
  });

  registerRequestDiagnostics(app);
  app.decorateRequest("authUserId", null);
  app.decorateRequest("operatorKeyId", null);

  app.addHook("onRequest", (request, reply, done) => {
    reply.header("x-request-id", request.id);
    done();
  });

  await app.register(sensible);
  await app.register(helmet, {
    contentSecurityPolicy: false,
  });
  await app.register(cors, {
    credentials: true,
    origin: [...config.corsAllowedOrigins],
  });

  await app.register(swagger, {
    openapi: {
      components: {
        securitySchemes: {
          bearerAuth: {
            bearerFormat: "JWT",
            scheme: "bearer",
            type: "http",
          },
        },
      },
      info: {
        title: "LingoTrip API",
        version: "0.1.0",
      },
    },
  });

  if (config.nodeEnv !== "production") {
    app.get(
      "/docs/openapi.json",
      {
        schema: {
          hide: true,
        },
      },
      () => app.swagger(),
    );
  }

  registerErrorHandling(app);
  registerHealthRoutes(app, options.readinessChecks ?? [], config.readinessTimeoutMs);
  registerMetrics(app, config, options.operationalMetricsSource);

  return app;
}
