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

  it("rejects invalid ports", () => {
    expect(() => loadConfig({ PORT: "70000" })).toThrow(ConfigurationError);
  });
});
