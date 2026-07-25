import type { FastifyInstance } from "fastify";
import { afterEach, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { loadConfig } from "../../src/config/env.js";

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
});
