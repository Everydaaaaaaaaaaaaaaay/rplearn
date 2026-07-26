import { describe, expect, it } from "vitest";
import {
  resolveTelemetrySettings,
  sanitizedTelemetryPath,
  TelemetryConfigurationError,
} from "../../src/config/telemetry.js";

describe("telemetry configuration and privacy", () => {
  it("is opt-in and derives stable API and worker service names", () => {
    expect(resolveTelemetrySettings({})).toEqual({ enabled: false });
    expect(
      resolveTelemetrySettings(
        {
          OTEL_EXPORTER_OTLP_ENDPOINT: "https://collector.example/otlp/",
          OTEL_TRACE_SAMPLE_RATIO: "0.25",
          OTEL_TRACING_ENABLED: "true",
        },
        "/app/dist/worker.js",
      ),
    ).toEqual({
      enabled: true,
      endpoint: "https://collector.example/otlp/v1/traces",
      exportTimeoutMs: 3000,
      sampleRatio: 0.25,
      serviceName: "lingotrip-worker",
      serviceVersion: "0.1.0",
    });
    expect(
      resolveTelemetrySettings(
        {
          APP_VERSION: "2026.07.26-abc123",
          OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: "https://collector.example/v1/traces",
          OTEL_SERVICE_NAME: "lingotrip-public-api",
          OTEL_TRACING_ENABLED: "true",
        },
        "/app/dist/server.js",
      ),
    ).toMatchObject({
      serviceName: "lingotrip-public-api",
      serviceVersion: "2026.07.26-abc123",
    });
  });

  it("rejects unsafe endpoints and unbounded sampling", () => {
    for (const environment of [
      {
        OTEL_TRACING_ENABLED: "true",
      },
      {
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT:
          "https://user:password@collector.example/v1/traces",
        OTEL_TRACING_ENABLED: "true",
      },
      {
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT:
          "https://collector.example/v1/traces?credential=value",
        OTEL_TRACING_ENABLED: "true",
      },
      {
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: "https://collector.example/v1/traces",
        OTEL_EXPORTER_OTLP_TRACES_TIMEOUT: "30000",
        OTEL_TRACING_ENABLED: "true",
      },
      {
        APP_VERSION: "release version with spaces",
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: "https://collector.example/v1/traces",
        OTEL_TRACING_ENABLED: "true",
      },
      {
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: "https://collector.example/v1/traces",
        OTEL_TRACE_SAMPLE_RATIO: "2",
        OTEL_TRACING_ENABLED: "true",
      },
    ]) {
      expect(() => resolveTelemetrySettings(environment)).toThrow(
        TelemetryConfigurationError,
      );
    }
  });

  it("removes query strings and normalizes identifiers in traced paths", () => {
    expect(
      sanitizedTelemetryPath(
        "/v1/media/019c0123-4567-789a-8bcd-ef0123456789?signature=secret",
      ),
    ).toBe("/v1/media/:id");
    expect(
      sanitizedTelemetryPath(
        "https://api.storekit.itunes.apple.com/inApps/v1/subscriptions/1234567890",
      ),
    ).toBe("/inApps/v1/subscriptions/:id");
    expect(sanitizedTelemetryPath("/v1/ai/completions")).toBe("/v1/ai/completions");
  });
});
