import { z } from "zod";

const booleanFromString = z
  .enum(["true", "false"])
  .transform((value) => value === "true");

const optionalSecret = z
  .string()
  .trim()
  .transform((value) => (value.length === 0 ? undefined : value))
  .optional();

const optionalPositiveInteger = z.preprocess(
  (value) =>
    typeof value === "string" && value.trim().length === 0 ? undefined : value,
  z.coerce.number().int().positive().optional(),
);

const rawEnvironmentSchema = z.object({
  APPLE_AUTH_ENABLED: booleanFromString.default(false),
  APPLE_BILLING_APP_APPLE_ID: optionalPositiveInteger,
  APPLE_BILLING_BUNDLE_ID: z.string().trim().min(3).default("com.tiantian.lingotrip"),
  APPLE_BILLING_ENABLED: booleanFromString.default(false),
  APPLE_BILLING_ENABLE_ONLINE_CHECKS: booleanFromString.default(true),
  APPLE_BILLING_ROOT_CA_CERTIFICATES_BASE64: z.string().default(""),
  APPLE_CHALLENGE_TTL_SECONDS: z.coerce.number().int().min(60).max(900).default(300),
  APPLE_CLIENT_IDS: z.string().default(""),
  APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64: optionalSecret,
  APPLE_CREDENTIAL_KEY_VERSION: optionalSecret,
  APPLE_JWKS_URL: z.url().default("https://appleid.apple.com/auth/keys"),
  APPLE_KEY_ID: optionalSecret,
  APPLE_PRIVATE_KEY_BASE64: optionalSecret,
  APPLE_REDIRECT_URI: optionalSecret.pipe(z.url().optional()),
  APPLE_TEAM_ID: optionalSecret,
  APPLE_TOKEN_ENDPOINT: z.url().default("https://appleid.apple.com/auth/token"),
  AI_RETRY_MAX_ATTEMPTS: z.coerce.number().int().min(1).max(3).default(2),
  AI_USAGE_RETENTION_DAYS: z.coerce.number().int().min(30).max(730).default(90),
  AI_USER_MINUTE_LIMIT: z.coerce.number().int().min(1).max(300).default(30),
  AUDIT_RETENTION_DAYS: z.coerce.number().int().min(30).max(2555).default(365),
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
  METRICS_BEARER_TOKEN: optionalSecret,
  METRICS_ENABLED: booleanFromString.default(true),
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
  aiRetryMaxAttempts: number;
  aiUsageRetentionDays: number;
  aiUserMinuteLimit: number;
  auditRetentionDays: number;
  appleAuthEnabled: boolean;
  appleBillingAppAppleId?: number;
  appleBillingBundleId: string;
  appleBillingEnabled: boolean;
  appleBillingEnableOnlineChecks: boolean;
  appleBillingRootCaCertificates: readonly Buffer[];
  appleChallengeTtlSeconds: number;
  appleClientIds: readonly string[];
  appleCredentialEncryptionKeyBase64?: string;
  appleCredentialKeyVersion?: string;
  appleJwksUrl: string;
  appleKeyId?: string;
  applePrivateKeyBase64?: string;
  appleRedirectUri?: string;
  appleTeamId?: string;
  appleTokenEndpoint: string;
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
  metricsBearerToken?: string;
  metricsEnabled: boolean;
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
  const appleClientIds = parseOrigins(result.data.APPLE_CLIENT_IDS);
  const appleBillingRootCaCertificates = parseOrigins(
    result.data.APPLE_BILLING_ROOT_CA_CERTIFICATES_BASE64,
  ).map((certificate) => Buffer.from(certificate, "base64"));
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
    result.data.NODE_ENV === "production" &&
    result.data.DEEPSEEK_API_KEY === undefined
  ) {
    issues.push("DEEPSEEK_API_KEY is required in production");
  }

  if (
    result.data.NODE_ENV === "production" &&
    result.data.METRICS_ENABLED &&
    (result.data.METRICS_BEARER_TOKEN?.length ?? 0) < 32
  ) {
    issues.push(
      "METRICS_BEARER_TOKEN must contain at least 32 characters when metrics are enabled",
    );
  }

  if (
    (result.data.SMTP_USER === undefined) !==
    (result.data.SMTP_PASSWORD === undefined)
  ) {
    issues.push("SMTP_USER and SMTP_PASSWORD must be provided together");
  }

  if (
    result.data.APPLE_AUTH_ENABLED &&
    (appleClientIds.length === 0 ||
      result.data.APPLE_TEAM_ID === undefined ||
      result.data.APPLE_KEY_ID === undefined ||
      result.data.APPLE_PRIVATE_KEY_BASE64 === undefined ||
      result.data.APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64 === undefined ||
      result.data.APPLE_CREDENTIAL_KEY_VERSION === undefined)
  ) {
    issues.push(
      "Apple auth requires client IDs, developer key, and credential encryption settings",
    );
  }

  if (
    result.data.APPLE_BILLING_ENABLED &&
    (result.data.APPLE_BILLING_APP_APPLE_ID === undefined ||
      appleBillingRootCaCertificates.length === 0)
  ) {
    issues.push(
      "Apple billing requires the App Apple ID and at least one DER root certificate",
    );
  }

  if (
    appleBillingRootCaCertificates.some((certificate) => certificate.byteLength === 0)
  ) {
    issues.push("Apple billing root certificates must be valid base64 values");
  }

  if (result.data.APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64 !== undefined) {
    const keyLength = Buffer.from(
      result.data.APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64,
      "base64",
    ).byteLength;
    if (keyLength !== 32) {
      issues.push("APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64 must decode to 32 bytes");
    }
  }

  if (issues.length > 0) {
    throw new ConfigurationError(issues);
  }

  return {
    aiRetryMaxAttempts: result.data.AI_RETRY_MAX_ATTEMPTS,
    aiUsageRetentionDays: result.data.AI_USAGE_RETENTION_DAYS,
    aiUserMinuteLimit: result.data.AI_USER_MINUTE_LIMIT,
    auditRetentionDays: result.data.AUDIT_RETENTION_DAYS,
    appleAuthEnabled: result.data.APPLE_AUTH_ENABLED,
    ...(result.data.APPLE_BILLING_APP_APPLE_ID === undefined
      ? {}
      : { appleBillingAppAppleId: result.data.APPLE_BILLING_APP_APPLE_ID }),
    appleBillingBundleId: result.data.APPLE_BILLING_BUNDLE_ID,
    appleBillingEnabled: result.data.APPLE_BILLING_ENABLED,
    appleBillingEnableOnlineChecks: result.data.APPLE_BILLING_ENABLE_ONLINE_CHECKS,
    appleBillingRootCaCertificates,
    appleChallengeTtlSeconds: result.data.APPLE_CHALLENGE_TTL_SECONDS,
    appleClientIds,
    ...(result.data.APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64 === undefined
      ? {}
      : {
          appleCredentialEncryptionKeyBase64:
            result.data.APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64,
        }),
    ...(result.data.APPLE_CREDENTIAL_KEY_VERSION === undefined
      ? {}
      : {
          appleCredentialKeyVersion: result.data.APPLE_CREDENTIAL_KEY_VERSION,
        }),
    appleJwksUrl: result.data.APPLE_JWKS_URL,
    ...(result.data.APPLE_KEY_ID === undefined
      ? {}
      : { appleKeyId: result.data.APPLE_KEY_ID }),
    ...(result.data.APPLE_PRIVATE_KEY_BASE64 === undefined
      ? {}
      : { applePrivateKeyBase64: result.data.APPLE_PRIVATE_KEY_BASE64 }),
    ...(result.data.APPLE_REDIRECT_URI === undefined
      ? {}
      : { appleRedirectUri: result.data.APPLE_REDIRECT_URI }),
    ...(result.data.APPLE_TEAM_ID === undefined
      ? {}
      : { appleTeamId: result.data.APPLE_TEAM_ID }),
    appleTokenEndpoint: result.data.APPLE_TOKEN_ENDPOINT,
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
    ...(result.data.METRICS_BEARER_TOKEN === undefined
      ? {}
      : { metricsBearerToken: result.data.METRICS_BEARER_TOKEN }),
    metricsEnabled: result.data.METRICS_ENABLED,
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
