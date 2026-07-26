import type { FastifyInstance } from "fastify";
import { afterEach, describe, expect, it } from "vitest";
import { vi } from "vitest";
import { buildApp } from "../../src/app.js";
import { loadConfig } from "../../src/config/env.js";
import type { OperationalMetricsSnapshot } from "../../src/modules/observability/metrics.js";

const operationalSnapshot: OperationalMetricsSnapshot = {
  aiRequests: [
    {
      count: 7,
      inputTokens: 120,
      outputTokens: 80,
      status: "succeeded",
      task: "conversation",
    },
  ],
  billingEventBacklog: [
    {
      count: 2,
      environment: "production",
      oldestAgeSeconds: 45,
    },
  ],
  billingReconciliationOverdue: [
    {
      count: 3,
      environment: "production",
    },
  ],
  jobCounts: [
    {
      count: 4,
      status: "pending",
      type: "auth.email_verification",
    },
  ],
  oldestPendingJobs: [
    {
      ageSeconds: 32,
      type: "auth.email_verification",
    },
  ],
  subscriptionCounts: [
    {
      count: 6,
      environment: "production",
      status: "active",
    },
  ],
};

describe("operational metrics", () => {
  let app: FastifyInstance | undefined;

  afterEach(async () => {
    await app?.close();
  });

  it("requires the configured token and exports low-cardinality metrics", async () => {
    app = await buildApp(
      loadConfig({
        METRICS_BEARER_TOKEN: "test-metrics-token",
        NODE_ENV: "test",
      }),
      { logger: false },
    );

    const unauthorized = await app.inject({
      method: "GET",
      url: "/internal/metrics",
    });
    expect(unauthorized.statusCode).toBe(401);

    await app.inject({
      method: "GET",
      url: "/health/live?ignored=high-cardinality-query",
    });
    const metrics = await app.inject({
      headers: {
        authorization: "Bearer test-metrics-token",
      },
      method: "GET",
      url: "/internal/metrics",
    });
    expect(metrics.statusCode).toBe(200);
    expect(metrics.body).toContain("lingotrip_http_requests_total");
    expect(metrics.body).toContain('route="/health/live"');
    expect(metrics.body).not.toContain("high-cardinality-query");
  });

  it("does not expose a route when metrics are disabled", async () => {
    app = await buildApp(
      loadConfig({
        METRICS_ENABLED: "false",
        NODE_ENV: "test",
      }),
      { logger: false },
    );

    expect(
      (
        await app.inject({
          method: "GET",
          url: "/internal/metrics",
        })
      ).statusCode,
    ).toBe(404);
  });

  it("exports cached, low-cardinality operational state without user data", async () => {
    const source = vi.fn().mockResolvedValue(operationalSnapshot);
    app = await buildApp(loadConfig({ NODE_ENV: "test" }), {
      logger: false,
      operationalMetricsSource: source,
    });

    const first = await app.inject({
      method: "GET",
      url: "/internal/metrics",
    });
    const second = await app.inject({
      method: "GET",
      url: "/internal/metrics",
    });

    expect(first.statusCode).toBe(200);
    expect(first.body).toContain(
      'lingotrip_jobs{status="pending",type="auth.email_verification"} 4',
    );
    expect(first.body).toContain(
      'lingotrip_billing_reconciliation_overdue{environment="production"} 3',
    );
    expect(first.body).toContain(
      'lingotrip_ai_requests_5m{status="succeeded",task="conversation"} 7',
    );
    expect(first.body).toContain(
      'lingotrip_ai_tokens_5m{direction="input",status="succeeded",task="conversation"} 120',
    );
    expect(first.body).toContain("lingotrip_operational_metrics_collection_success 1");
    expect(first.body).not.toContain("user_id");
    expect(source).toHaveBeenCalledTimes(1);
    expect(second.statusCode).toBe(200);
  });

  it("keeps metrics available and marks a failed operational collection", async () => {
    app = await buildApp(loadConfig({ NODE_ENV: "test" }), {
      logger: false,
      operationalMetricsSource: () => Promise.reject(new Error("database unavailable")),
    });

    const metrics = await app.inject({
      method: "GET",
      url: "/internal/metrics",
    });

    expect(metrics.statusCode).toBe(200);
    expect(metrics.body).toContain(
      "lingotrip_operational_metrics_collection_success 0",
    );
  });
});
