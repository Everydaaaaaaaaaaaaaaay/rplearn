export type TelemetrySettings =
  | Readonly<{ enabled: false }>
  | Readonly<{
      enabled: true;
      endpoint: string;
      exportTimeoutMs: number;
      sampleRatio: number;
      serviceName: string;
      serviceVersion: string;
    }>;

export class TelemetryConfigurationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "TelemetryConfigurationError";
  }
}

const SAFE_SEGMENT = /^[a-zA-Z][a-zA-Z0-9._-]{0,31}$/;

function optional(value: string | undefined): string | undefined {
  const trimmed = value?.trim();
  return trimmed === undefined || trimmed.length === 0 ? undefined : trimmed;
}

export function pathFromTelemetryUrl(
  value: string | undefined,
  origin = "https://local.invalid",
): string {
  try {
    return new URL(value ?? "/", origin).pathname;
  } catch {
    return "/";
  }
}

export function sanitizedTelemetryPath(value: string | undefined): string {
  const path = pathFromTelemetryUrl(value);
  const segments = path.split("/").map((segment) => {
    if (segment.length === 0) {
      return "";
    }
    return SAFE_SEGMENT.test(segment) ? segment : ":id";
  });
  return segments.join("/") || "/";
}

function endpoint(environment: NodeJS.ProcessEnv): string {
  const direct = optional(environment.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT);
  const base = optional(environment.OTEL_EXPORTER_OTLP_ENDPOINT);
  const raw =
    direct ??
    (base === undefined ? undefined : `${base.replace(/\/+$/, "")}/v1/traces`);
  if (raw === undefined) {
    throw new TelemetryConfigurationError(
      "An OTLP traces endpoint is required when tracing is enabled",
    );
  }
  let parsed: URL;
  try {
    parsed = new URL(raw);
  } catch {
    throw new TelemetryConfigurationError("The OTLP traces endpoint must be a URL");
  }
  if (
    !["http:", "https:"].includes(parsed.protocol) ||
    parsed.username.length > 0 ||
    parsed.password.length > 0 ||
    parsed.search.length > 0 ||
    parsed.hash.length > 0
  ) {
    throw new TelemetryConfigurationError(
      "The OTLP traces endpoint must use HTTP(S) without credentials, query, or fragment",
    );
  }
  return parsed.toString();
}

function processRole(entrypoint: string | undefined): "api" | "worker" {
  return entrypoint?.endsWith("/worker.js") || entrypoint?.endsWith("/worker.ts")
    ? "worker"
    : "api";
}

function serviceName(
  environment: NodeJS.ProcessEnv,
  entrypoint: string | undefined,
): string {
  const configured = optional(environment.OTEL_SERVICE_NAME);
  if (
    configured !== undefined &&
    /^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(configured)
  ) {
    return configured;
  }
  if (configured !== undefined) {
    throw new TelemetryConfigurationError(
      "OTEL_SERVICE_NAME must be a stable service identifier",
    );
  }
  return `lingotrip-${processRole(entrypoint)}`;
}

function stableIdentifier(value: string, name: string): string {
  if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(value)) {
    throw new TelemetryConfigurationError(`${name} must be a stable identifier`);
  }
  return value;
}

export function resolveTelemetrySettings(
  environment: NodeJS.ProcessEnv = process.env,
  entrypoint = process.argv[1],
): TelemetrySettings {
  const enabled = environment.OTEL_TRACING_ENABLED ?? "false";
  if (enabled !== "true" && enabled !== "false") {
    throw new TelemetryConfigurationError("OTEL_TRACING_ENABLED must be true or false");
  }
  if (enabled === "false") {
    return { enabled: false };
  }
  const sampleRatio = Number(environment.OTEL_TRACE_SAMPLE_RATIO ?? "0.1");
  if (!Number.isFinite(sampleRatio) || sampleRatio < 0 || sampleRatio > 1) {
    throw new TelemetryConfigurationError(
      "OTEL_TRACE_SAMPLE_RATIO must be between 0 and 1",
    );
  }
  const exportTimeoutMs = Number(
    environment.OTEL_EXPORTER_OTLP_TRACES_TIMEOUT ?? "3000",
  );
  if (
    !Number.isInteger(exportTimeoutMs) ||
    exportTimeoutMs < 100 ||
    exportTimeoutMs > 10_000
  ) {
    throw new TelemetryConfigurationError(
      "OTEL_EXPORTER_OTLP_TRACES_TIMEOUT must be between 100 and 10000 milliseconds",
    );
  }
  return {
    enabled: true,
    endpoint: endpoint(environment),
    exportTimeoutMs,
    sampleRatio,
    serviceName: serviceName(environment, entrypoint),
    serviceVersion: stableIdentifier(
      optional(environment.APP_VERSION) ?? "0.1.0",
      "APP_VERSION",
    ),
  };
}
