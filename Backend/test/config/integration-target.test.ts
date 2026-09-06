import { describe, expect, it, vi } from "vitest";
import { integrationConfig } from "../helpers/integration.js";

describe("isolated integration targets", () => {
  it("refuses missing, remote and ordinary developer databases before connecting", () => {
    vi.stubEnv("DATABASE_URL", "");
    vi.stubEnv("REDIS_URL", "");
    try {
      expect(() => integrationConfig()).toThrow("DATABASE_URL");
      for (const database of [
        "postgres://127.0.0.1:5432/lingotrip",
        "postgres://example.com/lingotrip_test_audit",
      ]) {
        expect(() =>
          integrationConfig({
            DATABASE_URL: database,
            REDIS_URL: "redis://127.0.0.1:56450",
          }),
        ).toThrow();
      }
      expect(() =>
        integrationConfig({
          DATABASE_URL: "postgres://127.0.0.1/lingotrip_test_audit",
          REDIS_URL: "redis://example.com",
        }),
      ).toThrow("REDIS_URL");
    } finally {
      vi.unstubAllEnvs();
    }
  });

  it("uses explicit isolated services even when a suite only overrides feature settings", () => {
    vi.stubEnv("DATABASE_URL", "postgres://127.0.0.1:55450/lingotrip_test_audit");
    vi.stubEnv("REDIS_URL", "redis://127.0.0.1:56450");
    try {
      const config = integrationConfig({ NODE_ENV: "test" });
      expect(config.databaseUrl).toBe(process.env.DATABASE_URL);
      expect(config.redisUrl).toBe(process.env.REDIS_URL);
    } finally {
      vi.unstubAllEnvs();
    }
  });
});
