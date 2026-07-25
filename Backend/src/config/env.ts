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
  AUTH_ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(3600).default(900),
  AUTH_ACTION_TOKEN_TTL_SECONDS: z.coerce
    .number()
    .int()
    .min(300)
    .max(86_400)
    .default(3600),
  AUTH_ACTION_URL_BASE: z.url().default("http://localhost:3000/auth"),
  AUTH_AUDIENCE: z.string().trim().min(1).default("lingotrip-clients"),
  AUTH_EMAIL_FROM: z
    .string()
    .trim()
    .min(3)
    .default("LingoTrip <no-reply@local.lingotrip>"),
  AUTH_ISSUER: z.url().default("https://api.lingotrip.app"),
  AUTH_JWT_KEY_ID: optionalSecret,
  AUTH_JWT_PRIVATE_KEY_BASE64: optionalSecret,
  AUTH_JWT_PUBLIC_KEY_BASE64: optionalSecret,
  AUTH_REFRESH_TOKEN_TTL_DAYS: z.coerce.number().int().min(1).max(180).default(30),
  AUTH_TOKEN_HASH_PEPPER: optionalSecret,
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
  SMTP_HOST: optionalSecret,
  SMTP_PASSWORD: optionalSecret,
  SMTP_PORT: z.coerce.number().int().min(1).max(65_535).default(1025),
  SMTP_SECURE: booleanFromString.default(false),
  SMTP_USER: optionalSecret,
  TRUST_PROXY: booleanFromString.default(false),
});

export type RuntimeConfig = Readonly<{
  authAccessTokenTtlSeconds: number;
  authActionTokenTtlSeconds: number;
  authActionUrlBase: string;
  authAudience: string;
  authEmailFrom: string;
  authIssuer: string;
  authJwtKeyId?: string;
  authJwtPrivateKeyBase64?: string;
  authJwtPublicKeyBase64?: string;
  authRefreshTokenTtlDays: number;
  authTokenHashPepper: string;
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
  smtpHost: string;
  smtpPassword?: string;
  smtpPort: number;
  smtpSecure: boolean;
  smtpUser?: string;
  trustProxy: boolean;
}>;

const DEVELOPMENT_DATABASE_URL =
  "postgres://lingotrip:lingotrip_dev@127.0.0.1:54329/lingotrip";
const DEVELOPMENT_REDIS_URL = "redis://127.0.0.1:63799";
const DEVELOPMENT_AUTH_PEPPER = "local-only-auth-token-pepper-change-before-production";
const DEVELOPMENT_SMTP_HOST = "127.0.0.1";

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

  if (
    result.data.NODE_ENV === "production" &&
    result.data.AUTH_TOKEN_HASH_PEPPER === undefined
  ) {
    issues.push("AUTH_TOKEN_HASH_PEPPER is required in production");
  }

  if (
    result.data.NODE_ENV === "production" &&
    (result.data.AUTH_TOKEN_HASH_PEPPER?.length ?? 0) < 32
  ) {
    issues.push("AUTH_TOKEN_HASH_PEPPER must contain at least 32 characters");
  }

  if (
    result.data.NODE_ENV === "production" &&
    (result.data.AUTH_JWT_PRIVATE_KEY_BASE64 === undefined ||
      result.data.AUTH_JWT_PUBLIC_KEY_BASE64 === undefined ||
      result.data.AUTH_JWT_KEY_ID === undefined)
  ) {
    issues.push("persistent AUTH_JWT keys and key ID are required in production");
  }

  if (result.data.NODE_ENV === "production" && result.data.SMTP_HOST === undefined) {
    issues.push("SMTP_HOST is required in production");
  }

  if (
    (result.data.SMTP_USER === undefined) !==
    (result.data.SMTP_PASSWORD === undefined)
  ) {
    issues.push("SMTP_USER and SMTP_PASSWORD must be provided together");
  }

  if (issues.length > 0) {
    throw new ConfigurationError(issues);
  }

  return {
    authAccessTokenTtlSeconds: result.data.AUTH_ACCESS_TOKEN_TTL_SECONDS,
    authActionTokenTtlSeconds: result.data.AUTH_ACTION_TOKEN_TTL_SECONDS,
    authActionUrlBase: result.data.AUTH_ACTION_URL_BASE,
    authAudience: result.data.AUTH_AUDIENCE,
    authEmailFrom: result.data.AUTH_EMAIL_FROM,
    authIssuer: result.data.AUTH_ISSUER,
    ...(result.data.AUTH_JWT_KEY_ID === undefined
      ? {}
      : { authJwtKeyId: result.data.AUTH_JWT_KEY_ID }),
    ...(result.data.AUTH_JWT_PRIVATE_KEY_BASE64 === undefined
      ? {}
      : { authJwtPrivateKeyBase64: result.data.AUTH_JWT_PRIVATE_KEY_BASE64 }),
    ...(result.data.AUTH_JWT_PUBLIC_KEY_BASE64 === undefined
      ? {}
      : { authJwtPublicKeyBase64: result.data.AUTH_JWT_PUBLIC_KEY_BASE64 }),
    authRefreshTokenTtlDays: result.data.AUTH_REFRESH_TOKEN_TTL_DAYS,
    authTokenHashPepper: result.data.AUTH_TOKEN_HASH_PEPPER ?? DEVELOPMENT_AUTH_PEPPER,
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
    smtpHost: result.data.SMTP_HOST ?? DEVELOPMENT_SMTP_HOST,
    ...(result.data.SMTP_PASSWORD === undefined
      ? {}
      : { smtpPassword: result.data.SMTP_PASSWORD }),
    smtpPort: result.data.SMTP_PORT,
    smtpSecure: result.data.SMTP_SECURE,
    ...(result.data.SMTP_USER === undefined ? {} : { smtpUser: result.data.SMTP_USER }),
    trustProxy: result.data.TRUST_PROXY,
  };
}
