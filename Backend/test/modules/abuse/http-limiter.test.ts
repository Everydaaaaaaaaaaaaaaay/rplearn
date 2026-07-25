import { describe, expect, it } from "vitest";
import { buildApp } from "../../../src/app.js";
import { loadConfig } from "../../../src/config/env.js";
import type { RedisResource } from "../../../src/infrastructure/redis/client.js";
import { registerHttpAbuseProtection } from "../../../src/modules/abuse/http-limiter.js";

class FakeRedis implements RedisResource {
  readonly counts = new Map<string, number>();
  fail = false;

  close(): Promise<void> {
    return Promise.resolve();
  }

  connect(): Promise<void> {
    return Promise.resolve();
  }

  consumeFixedWindow(key: string): Promise<number> {
    if (this.fail) {
      return Promise.reject(new Error("redis unavailable"));
    }
    const count = (this.counts.get(key) ?? 0) + 1;
    this.counts.set(key, count);
    return Promise.resolve(count);
  }

  onError(listener: (error: Error) => void): void {
    void listener;
  }
  ping(): Promise<void> {
    return Promise.resolve();
  }
  putOneTime(): Promise<void> {
    return Promise.resolve();
  }
  takeOneTime(): Promise<string | null> {
    return Promise.resolve(null);
  }
}

describe("HTTP abuse protection", () => {
  it("limits normalized account identities without putting PII in Redis keys", async () => {
    const config = loadConfig({
      AUTH_LOGIN_ACCOUNT_15M_LIMIT: "1",
      AUTH_LOGIN_IP_15M_LIMIT: "10",
      HTTP_GLOBAL_IP_MINUTE_LIMIT: "100",
      NODE_ENV: "test",
    });
    const redis = new FakeRedis();
    const app = await buildApp(config, { logger: false });
    registerHttpAbuseProtection(app, config, redis);
    app.post("/v1/auth/login", () => ({ ok: true }));

    const first = await app.inject({
      method: "POST",
      payload: { email: "Traveler@Example.com" },
      url: "/v1/auth/login",
    });
    expect(first.statusCode).toBe(200);
    expect(first.headers["ratelimit-remaining"]).toBe("0");

    const blocked = await app.inject({
      method: "POST",
      payload: { email: " traveler@example.COM " },
      url: "/v1/auth/login",
    });
    expect(blocked.statusCode).toBe(429);
    expect(blocked.headers["retry-after"]).toBe("900");
    expect(blocked.json<{ code: string }>().code).toBe("RATE_LIMIT_EXCEEDED");
    expect([...redis.counts.keys()].join(" ")).not.toContain("traveler@example");
    await app.close();
  });

  it("fails closed for auth and open for ordinary APIs when Redis is unavailable", async () => {
    const config = loadConfig({ NODE_ENV: "test" });
    const redis = new FakeRedis();
    redis.fail = true;
    const app = await buildApp(config, { logger: false });
    registerHttpAbuseProtection(app, config, redis);
    app.post("/v1/auth/login", () => ({ ok: true }));
    app.get("/v1/probe", () => ({ ok: true }));

    const auth = await app.inject({
      method: "POST",
      payload: { email: "traveler@example.com" },
      url: "/v1/auth/login",
    });
    expect(auth.statusCode).toBe(503);
    expect(auth.json<{ code: string }>().code).toBe("ABUSE_PROTECTION_UNAVAILABLE");

    const ordinary = await app.inject({
      method: "GET",
      url: "/v1/probe",
    });
    expect(ordinary.statusCode).toBe(200);
    await app.close();
  });
});
