import { describe, expect, it } from "vitest";
import { ConfigurationError, loadConfig } from "../../src/config/env.js";

describe("loadConfig", () => {
  it("provides safe development defaults", () => {
    const config = loadConfig({});

    expect(config).toMatchObject({
      corsAllowedOrigins: ["http://localhost:3000"],
      deepSeekBaseUrl: "https://api.deepseek.com",
      host: "127.0.0.1",
      nodeEnv: "development",
      port: 8080,
      trustProxy: false,
    });
    expect(config.deepSeekApiKey).toBeUndefined();
  });

  it("parses comma separated origins and an explicit boolean", () => {
    const config = loadConfig({
      CORS_ALLOWED_ORIGINS: "https://app.example.com, https://admin.example.com",
      TRUST_PROXY: "true",
    });

    expect(config.corsAllowedOrigins).toEqual([
      "https://app.example.com",
      "https://admin.example.com",
    ]);
    expect(config.trustProxy).toBe(true);
  });

  it("rejects wildcard CORS in production", () => {
    expect(() =>
      loadConfig({
        CORS_ALLOWED_ORIGINS: "*",
        NODE_ENV: "production",
      }),
    ).toThrow(ConfigurationError);
  });

  it("requires explicit persistent dependencies in production", () => {
    try {
      loadConfig({
        CORS_ALLOWED_ORIGINS: "https://app.example.com",
        NODE_ENV: "production",
      });
      expect.unreachable("production configuration should be rejected");
    } catch (error) {
      expect(error).toBeInstanceOf(ConfigurationError);
      if (!(error instanceof ConfigurationError)) {
        return;
      }
      expect(error.issues).toContain("DATABASE_URL is required in production");
      expect(error.issues).toContain("REDIS_URL is required in production");
      expect(error.issues).toContain("DEEPSEEK_API_KEY is required in production");
      expect(error.issues).toContain(
        "JOB_PAYLOAD_ENCRYPTION_KEY_BASE64 and JOB_PAYLOAD_KEY_VERSION are required in production",
      );
      expect(error.issues).toContain(
        "METRICS_BEARER_TOKEN must contain at least 32 characters when metrics are enabled",
      );
    }
  });

  it("rejects invalid ports", () => {
    expect(() => loadConfig({ PORT: "70000" })).toThrow(ConfigurationError);
  });

  it("requires the complete Apple credential set when Apple auth is enabled", () => {
    expect(() =>
      loadConfig({
        APPLE_AUTH_ENABLED: "true",
        APPLE_CLIENT_IDS: "com.example.app",
      }),
    ).toThrow(ConfigurationError);
  });

  it("requires App Store identity and root certificates for Apple billing", () => {
    expect(() =>
      loadConfig({
        APPLE_BILLING_APP_APPLE_ID: "",
        APPLE_BILLING_ENABLED: "true",
      }),
    ).toThrow(ConfigurationError);
  });

  it("rejects malformed historical job encryption keys", () => {
    expect(() =>
      loadConfig({
        JOB_PAYLOAD_PREVIOUS_KEYS: "jobs-v1=not-a-32-byte-key",
      }),
    ).toThrow(ConfigurationError);
  });

  it("rejects duplicate JWT key IDs during rotation", () => {
    expect(() =>
      loadConfig({
        AUTH_JWT_KEY_ID: "same-key",
        AUTH_JWT_PREVIOUS_PUBLIC_KEYS: "same-key=YWJj",
      }),
    ).toThrow(ConfigurationError);
  });
});
