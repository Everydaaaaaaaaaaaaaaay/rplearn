import { afterEach, describe, expect, it } from "vitest";
import type { FastifyInstance } from "fastify";
import { buildApp } from "../../src/app.js";
import { loadConfig } from "../../src/config/env.js";

describe("health routes", () => {
  let app: FastifyInstance | undefined;

  afterEach(async () => {
    await app?.close();
  });

  it("reports liveness without exposing internals", async () => {
    app = await buildApp(loadConfig({ NODE_ENV: "test" }), { logger: false });

    const response = await app.inject({
      method: "GET",
      url: "/health/live",
    });

    expect(response.statusCode).toBe(200);
    expect(response.json<{ status: string }>()).toEqual({ status: "ok" });
    expect(response.headers["x-request-id"]).toBeTypeOf("string");
  });

  it("uses a stable public not-found error", async () => {
    app = await buildApp(loadConfig({ NODE_ENV: "test" }), { logger: false });

    const response = await app.inject({
      method: "GET",
      url: "/missing",
    });

    expect(response.statusCode).toBe(404);
    const body = response.json<{
      code: string;
      message: string;
      requestId: string;
    }>();
    expect(body).toMatchObject({
      code: "ROUTE_NOT_FOUND",
      message: "The requested resource does not exist.",
    });
    expect(body.requestId).toBeTypeOf("string");
  });
});
