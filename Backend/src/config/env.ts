import { z } from "zod";

const booleanFromString = z
  .enum(["true", "false"])
  .transform((value) => value === "true");

const optionalSecret = z
  .string()
  .trim()
  .transform((value) => (value.length === 0 ? undefined : value))
  .optional();

const rawEnvironmentSchema = z.object({
  CORS_ALLOWED_ORIGINS: z.string().default("http://localhost:3000"),
  DATABASE_CONNECT_TIMEOUT_MS: z.coerce
    .number()
    .int()
    .min(100)
    .max(60_000)
    .default(5000),
  DATABASE_IDLE_TIMEOUT_MS: z.coerce
    .number()
    .int()
    .min(1000)
    .max(300_000)
    .default(20_000),
  DATABASE_MAX_CONNECTIONS: z.coerce.number().int().min(1).max(100).default(10),
  DATABASE_URL: z.url().optional(),
  DEEPSEEK_API_KEY: optionalSecret,
  DEEPSEEK_BASE_URL: z.url().default("https://api.deepseek.com"),
  HOST: z.string().trim().min(1).default("127.0.0.1"),
  LOG_LEVEL: z
    .enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"])
    .default("info"),
  NODE_ENV: z.enum(["development", "test", "production"]).default("development"),
  PORT: z.coerce.number().int().min(1).max(65_535).default(8080),
  READINESS_TIMEOUT_MS: z.coerce.number().int().min(100).max(30_000).default(2000),
  REDIS_CONNECT_TIMEOUT_MS: z.coerce.number().int().min(100).max(60_000).default(5000),
  REDIS_URL: z.url().optional(),
  REQUEST_BODY_LIMIT_BYTES: z.coerce
    .number()
    .int()
    .min(1024)
    .max(10 * 1024 * 1024)
    .default(1024 * 1024),
  REQUEST_TIMEOUT_MS: z.coerce.number().int().min(1000).max(120_000).default(30_000),
  SHUTDOWN_GRACE_MS: z.coerce.number().int().min(1000).max(60_000).default(10_000),
  TRUST_PROXY: booleanFromString.default(false),
});

export type RuntimeConfig = Readonly<{
  corsAllowedOrigins: readonly string[];
  databaseConnectTimeoutMs: number;
  databaseIdleTimeoutMs: number;
  databaseMaxConnections: number;
  databaseUrl: string;
  deepSeekApiKey?: string;
  deepSeekBaseUrl: string;
  host: string;
  logLevel: "fatal" | "error" | "warn" | "info" | "debug" | "trace" | "silent";
  nodeEnv: "development" | "test" | "production";
  port: number;
  readinessTimeoutMs: number;
  redisConnectTimeoutMs: number;
  redisUrl: string;
  requestBodyLimitBytes: number;
  requestTimeoutMs: number;
  shutdownGraceMs: number;
  trustProxy: boolean;
}>;

const DEVELOPMENT_DATABASE_URL =
  "postgres://lingotrip:lingotrip_dev@127.0.0.1:54329/lingotrip";
const DEVELOPMENT_REDIS_URL = "redis://127.0.0.1:63799";

export class ConfigurationError extends Error {
  readonly issues: readonly string[];

  constructor(issues: readonly string[]) {
    super(`Invalid runtime configuration: ${issues.join("; ")}`);
    this.name = "ConfigurationError";
    this.issues = issues;
  }
}

function parseOrigins(raw: string): readonly string[] {
  return raw
    .split(",")
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
}

export function loadConfig(
  environment: NodeJS.ProcessEnv = process.env,
): RuntimeConfig {
  const result = rawEnvironmentSchema.safeParse(environment);

  if (!result.success) {
    throw new ConfigurationError(
      result.error.issues.map(
        (issue) => `${issue.path.join(".") || "environment"}: ${issue.message}`,
      ),
    );
  }

  const corsAllowedOrigins = parseOrigins(result.data.CORS_ALLOWED_ORIGINS);
  const issues: string[] = [];

  if (corsAllowedOrigins.length === 0) {
    issues.push("CORS_ALLOWED_ORIGINS must contain at least one origin");
  }

  if (
    result.data.NODE_ENV === "production" &&
    corsAllowedOrigins.some((origin) => origin === "*")
  ) {
    issues.push("CORS_ALLOWED_ORIGINS cannot contain * in production");
  }

  if (result.data.NODE_ENV === "production" && result.data.DATABASE_URL === undefined) {
    issues.push("DATABASE_URL is required in production");
  }

  if (result.data.NODE_ENV === "production" && result.data.REDIS_URL === undefined) {
    issues.push("REDIS_URL is required in production");
  }

  if (issues.length > 0) {
    throw new ConfigurationError(issues);
  }

  return {
    corsAllowedOrigins,
    databaseConnectTimeoutMs: result.data.DATABASE_CONNECT_TIMEOUT_MS,
    databaseIdleTimeoutMs: result.data.DATABASE_IDLE_TIMEOUT_MS,
    databaseMaxConnections: result.data.DATABASE_MAX_CONNECTIONS,
    databaseUrl: result.data.DATABASE_URL ?? DEVELOPMENT_DATABASE_URL,
    ...(result.data.DEEPSEEK_API_KEY === undefined
      ? {}
      : { deepSeekApiKey: result.data.DEEPSEEK_API_KEY }),
    deepSeekBaseUrl: result.data.DEEPSEEK_BASE_URL,
    host: result.data.HOST,
    logLevel: result.data.LOG_LEVEL,
    nodeEnv: result.data.NODE_ENV,
    port: result.data.PORT,
    readinessTimeoutMs: result.data.READINESS_TIMEOUT_MS,
    redisConnectTimeoutMs: result.data.REDIS_CONNECT_TIMEOUT_MS,
    redisUrl: result.data.REDIS_URL ?? DEVELOPMENT_REDIS_URL,
    requestBodyLimitBytes: result.data.REQUEST_BODY_LIMIT_BYTES,
    requestTimeoutMs: result.data.REQUEST_TIMEOUT_MS,
    shutdownGraceMs: result.data.SHUTDOWN_GRACE_MS,
    trustProxy: result.data.TRUST_PROXY,
  };
}
