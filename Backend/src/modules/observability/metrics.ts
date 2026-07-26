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

export type OperationalMetricsSnapshot = Readonly<{
  aiRequests: readonly Readonly<{
    count: number;
    inputTokens: number;
    outputTokens: number;
    status: string;
    task: string;
  }>[];
  billingEventBacklog: readonly Readonly<{
    count: number;
    environment: string;
    oldestAgeSeconds: number;
  }>[];
  billingReconciliationOverdue: readonly Readonly<{
    count: number;
    environment: string;
  }>[];
  jobCounts: readonly Readonly<{
    count: number;
    status: string;
    type: string;
  }>[];
  oldestPendingJobs: readonly Readonly<{
    ageSeconds: number;
    type: string;
  }>[];
  subscriptionCounts: readonly Readonly<{
    count: number;
    environment: string;
    status: string;
  }>[];
}>;

export type OperationalMetricsSource = () => Promise<OperationalMetricsSnapshot>;

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

export function registerMetrics(
  app: FastifyInstance,
  config: RuntimeConfig,
  operationalSource?: OperationalMetricsSource,
): void {
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
  const operationalCollectionSuccess = new Gauge({
    help: "Whether the latest operational database metrics collection succeeded.",
    name: "lingotrip_operational_metrics_collection_success",
    registers: [registry],
  });
  const operationalCollectionTimestamp = new Gauge({
    help: "Unix timestamp of the latest successful operational metrics collection.",
    name: "lingotrip_operational_metrics_collection_timestamp_seconds",
    registers: [registry],
  });
  const jobs = new Gauge({
    help: "Persisted background jobs by bounded type and status.",
    labelNames: ["type", "status"] as const,
    name: "lingotrip_jobs",
    registers: [registry],
  });
  const oldestPendingJob = new Gauge({
    help: "Age in seconds of the oldest pending job by bounded type.",
    labelNames: ["type"] as const,
    name: "lingotrip_job_oldest_pending_age_seconds",
    registers: [registry],
  });
  const subscriptions = new Gauge({
    help: "Persisted subscriptions by environment and entitlement status.",
    labelNames: ["environment", "status"] as const,
    name: "lingotrip_subscriptions",
    registers: [registry],
  });
  const billingReconciliationOverdue = new Gauge({
    help: "Apple subscriptions whose active reconciliation deadline is overdue.",
    labelNames: ["environment"] as const,
    name: "lingotrip_billing_reconciliation_overdue",
    registers: [registry],
  });
  const billingEventBacklog = new Gauge({
    help: "Unprocessed App Store server notifications.",
    labelNames: ["environment"] as const,
    name: "lingotrip_billing_event_backlog",
    registers: [registry],
  });
  const billingEventOldestAge = new Gauge({
    help: "Age in seconds of the oldest unprocessed App Store notification.",
    labelNames: ["environment"] as const,
    name: "lingotrip_billing_event_oldest_age_seconds",
    registers: [registry],
  });
  const aiRequests = new Gauge({
    help: "Persisted AI requests observed during the trailing five-minute window.",
    labelNames: ["task", "status"] as const,
    name: "lingotrip_ai_requests_5m",
    registers: [registry],
  });
  const aiTokens = new Gauge({
    help: "Persisted AI tokens observed during the trailing five-minute window.",
    labelNames: ["task", "status", "direction"] as const,
    name: "lingotrip_ai_tokens_5m",
    registers: [registry],
  });
  const startedAt = new WeakMap<FastifyRequest, bigint>();
  const active = new WeakSet<FastifyRequest>();
  let collection: Promise<void> | undefined;
  let lastCollectionAttempt = 0;

  const applyOperationalSnapshot = (snapshot: OperationalMetricsSnapshot): void => {
    jobs.reset();
    oldestPendingJob.reset();
    subscriptions.reset();
    billingReconciliationOverdue.reset();
    billingEventBacklog.reset();
    billingEventOldestAge.reset();
    aiRequests.reset();
    aiTokens.reset();
    for (const row of snapshot.jobCounts) {
      jobs.set({ status: row.status, type: row.type }, row.count);
    }
    for (const row of snapshot.oldestPendingJobs) {
      oldestPendingJob.set({ type: row.type }, row.ageSeconds);
    }
    for (const row of snapshot.subscriptionCounts) {
      subscriptions.set(
        { environment: row.environment, status: row.status },
        row.count,
      );
    }
    for (const row of snapshot.billingReconciliationOverdue) {
      billingReconciliationOverdue.set({ environment: row.environment }, row.count);
    }
    for (const row of snapshot.billingEventBacklog) {
      billingEventBacklog.set({ environment: row.environment }, row.count);
      billingEventOldestAge.set({ environment: row.environment }, row.oldestAgeSeconds);
    }
    for (const row of snapshot.aiRequests) {
      aiRequests.set({ status: row.status, task: row.task }, row.count);
      aiTokens.set(
        { direction: "input", status: row.status, task: row.task },
        row.inputTokens,
      );
      aiTokens.set(
        { direction: "output", status: row.status, task: row.task },
        row.outputTokens,
      );
    }
    operationalCollectionSuccess.set(1);
    operationalCollectionTimestamp.set(Date.now() / 1000);
  };

  const collectOperationalMetrics = async (): Promise<void> => {
    if (operationalSource === undefined) {
      return;
    }
    const now = Date.now();
    if (collection !== undefined) {
      return collection;
    }
    if (now - lastCollectionAttempt < 10_000) {
      return;
    }
    lastCollectionAttempt = now;
    collection = operationalSource()
      .then(applyOperationalSnapshot)
      .catch((error: unknown) => {
        operationalCollectionSuccess.set(0);
        app.log.warn(
          {
            errorName: error instanceof Error ? error.name : "UnknownError",
          },
          "Operational metrics collection failed",
        );
      })
      .finally(() => {
        collection = undefined;
      });
    return collection;
  };

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
      await collectOperationalMetrics();
      return reply
        .header("content-type", registry.contentType)
        .send(await registry.metrics());
    },
  );
}
