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
    expect(config.openRouterApiKey).toBeUndefined();
    expect(config.openRouterBaseUrl).toBe("https://openrouter.ai/api/v1");
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

  it("validates opt-in tracing before the service starts", () => {
    expect(() =>
      loadConfig({
        OTEL_TRACING_ENABLED: "true",
      }),
    ).toThrow(ConfigurationError);
    expect(() =>
      loadConfig({
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: "https://collector.example/v1/traces",
        OTEL_TRACE_SAMPLE_RATIO: "0.1",
        OTEL_TRACING_ENABLED: "true",
      }),
    ).not.toThrow();
  });

  it("requires long, identified operator keys for the admin API", () => {
    expect(() =>
      loadConfig({
        ADMIN_API_ENABLED: "true",
        ADMIN_API_KEYS: "operator=short",
      }),
    ).toThrow(ConfigurationError);

    const config = loadConfig({
      ADMIN_API_ENABLED: "true",
      ADMIN_API_KEYS:
        "primary=primary-operator-token-with-at-least-32-characters,rotation=rotation-operator-token-with-at-least-32-characters",
      AI_DEEPSEEK_ALLOWED_MODELS: "deepseek-v4-flash,deepseek-v4-pro",
    });
    expect(config.adminApiKeys.map((key) => key.keyId)).toEqual([
      "primary",
      "rotation",
    ]);
    expect(config.aiDeepSeekAllowedModels).toEqual([
      "deepseek-v4-flash",
      "deepseek-v4-pro",
    ]);
  });

  it("rejects wildcard CORS in production", () => {
    expect(() =>
      loadConfig({
        CORS_ALLOWED_ORIGINS: "*",
        NODE_ENV: "production",
      }),
    ).toThrow(ConfigurationError);
  });

  it("requires a reviewed settlement rate with OpenRouter credentials", () => {
    expect(() => loadConfig({ OPENROUTER_API_KEY: "test-openrouter-key" })).toThrow(
      ConfigurationError,
    );
    const config = loadConfig({
      OPENROUTER_API_KEY: "test-openrouter-key",
      OPENROUTER_USD_TO_CNY: "7.200000",
    });
    expect(config).toMatchObject({
      openRouterApiKey: "test-openrouter-key",
      openRouterUsdToCny: "7.200000",
    });
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
      expect(error.issues).toContain(
        "MEDIA_STORAGE_ENABLED must be true in production",
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

  it("parses complete App Store Server API reconciliation settings", () => {
    const config = loadConfig({
      APPLE_BILLING_APP_APPLE_ID: "123456789",
      APPLE_BILLING_BUNDLE_ID: "com.example.app",
      APPLE_BILLING_ENABLED: "true",
      APPLE_BILLING_ISSUER_ID: "019c0123-4567-789a-8bcd-ef0123456789",
      APPLE_BILLING_KEY_ID: "TESTKEY123",
      APPLE_BILLING_PRIVATE_KEY_BASE64: Buffer.from(
        "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----",
      ).toString("base64"),
      APPLE_BILLING_RECONCILE_BATCH_SIZE: "25",
      APPLE_BILLING_ROOT_CA_CERTIFICATES_BASE64:
        Buffer.from("certificate").toString("base64"),
    });

    expect(config).toMatchObject({
      appleBillingEnabled: true,
      appleBillingIssuerId: "019c0123-4567-789a-8bcd-ef0123456789",
      appleBillingKeyId: "TESTKEY123",
      appleBillingReconcileBatchSize: 25,
    });
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

  it("requires a bucket and complete static credentials for enabled media", () => {
    expect(() =>
      loadConfig({
        MEDIA_S3_ACCESS_KEY_ID: "incomplete",
        MEDIA_STORAGE_ENABLED: "true",
      }),
    ).toThrow(ConfigurationError);
  });
});
