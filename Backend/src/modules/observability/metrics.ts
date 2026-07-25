import { createHash, timingSafeEqual } from "node:crypto";
import type { FastifyInstance, FastifyRequest } from "fastify";
import {
  collectDefaultMetrics,
  Counter,
  Gauge,
  Histogram,
  Registry,
} from "prom-client";
import type { RuntimeConfig } from "../../config/env.js";

function authorized(request: FastifyRequest, expectedToken?: string): boolean {
  if (expectedToken === undefined) {
    return true;
  }
  const supplied = /^Bearer ([^\s]+)$/i.exec(request.headers.authorization ?? "")?.[1];
  if (supplied === undefined) {
    return false;
  }
  const expectedHash = createHash("sha256").update(expectedToken).digest();
  const suppliedHash = createHash("sha256").update(supplied).digest();
  return timingSafeEqual(expectedHash, suppliedHash);
}

function routeLabel(request: FastifyRequest): string {
  return request.routeOptions.url ?? "unmatched";
}

export function registerMetrics(app: FastifyInstance, config: RuntimeConfig): void {
  if (!config.metricsEnabled) {
    return;
  }
  const registry = new Registry();
  collectDefaultMetrics({
    prefix: "lingotrip_",
    register: registry,
  });
  const requestCount = new Counter({
    help: "Completed HTTP requests.",
    labelNames: ["method", "route", "status_family"] as const,
    name: "lingotrip_http_requests_total",
    registers: [registry],
  });
  const requestDuration = new Histogram({
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30, 60],
    help: "HTTP request duration in seconds.",
    labelNames: ["method", "route", "status_family"] as const,
    name: "lingotrip_http_request_duration_seconds",
    registers: [registry],
  });
  const activeRequests = new Gauge({
    help: "HTTP requests currently in progress.",
    labelNames: ["method"] as const,
    name: "lingotrip_http_active_requests",
    registers: [registry],
  });
  const startedAt = new WeakMap<FastifyRequest, bigint>();
  const active = new WeakSet<FastifyRequest>();

  app.addHook("onRequest", (request, _reply, done) => {
    startedAt.set(request, process.hrtime.bigint());
    active.add(request);
    activeRequests.inc({ method: request.method });
    done();
  });

  const finalize = (request: FastifyRequest, statusCode: number): void => {
    const start = startedAt.get(request);
    const labels = {
      method: request.method,
      route: routeLabel(request),
      status_family: `${String(Math.floor(statusCode / 100))}xx`,
    };
    requestCount.inc(labels);
    if (start !== undefined) {
      requestDuration.observe(
        labels,
        Number(process.hrtime.bigint() - start) / 1_000_000_000,
      );
    }
    if (active.delete(request)) {
      activeRequests.dec({ method: request.method });
    }
  };

  app.addHook("onResponse", (request, reply, done) => {
    finalize(request, reply.statusCode);
    done();
  });
  app.addHook("onRequestAbort", (request, done) => {
    finalize(request, 499);
    done();
  });

  app.get(
    "/internal/metrics",
    {
      schema: {
        hide: true,
      },
    },
    async (request, reply) => {
      if (!authorized(request, config.metricsBearerToken)) {
        return reply.status(401).send({
          code: "UNAUTHORIZED",
          message: "A valid metrics token is required.",
          requestId: request.id,
        });
      }
      return reply
        .header("content-type", registry.contentType)
        .send(await registry.metrics());
    },
  );
}
