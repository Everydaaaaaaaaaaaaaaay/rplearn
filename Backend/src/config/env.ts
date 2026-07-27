import { createHash } from "node:crypto";
import { z } from "zod";
import { resolveTelemetrySettings, TelemetryConfigurationError } from "./telemetry.js";

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
  ADMIN_API_ENABLED: booleanFromString.default(false),
  ADMIN_API_KEYS: z.string().default(""),
  APPLE_AUTH_ENABLED: booleanFromString.default(false),
  APPLE_BILLING_APP_APPLE_ID: optionalPositiveInteger,
  APPLE_BILLING_BUNDLE_ID: z.string().trim().min(3).default("com.tiantian.lingotrip"),
  APPLE_BILLING_ENABLED: booleanFromString.default(false),
  APPLE_BILLING_ENABLE_ONLINE_CHECKS: booleanFromString.default(true),
  APPLE_BILLING_ISSUER_ID: optionalSecret,
  APPLE_BILLING_KEY_ID: optionalSecret,
  APPLE_BILLING_PRIVATE_KEY_BASE64: optionalSecret,
  APPLE_BILLING_RECONCILE_ACTIVE_HOURS: z.coerce
    .number()
    .int()
    .min(1)
    .max(24)
    .default(6),
  APPLE_BILLING_RECONCILE_BATCH_SIZE: z.coerce
    .number()
    .int()
    .min(1)
    .max(500)
    .default(100),
  APPLE_BILLING_RECONCILE_INACTIVE_HOURS: z.coerce
    .number()
    .int()
    .min(1)
    .max(168)
    .default(24),
  APPLE_BILLING_RECONCILE_RETRY_MINUTES: z.coerce
    .number()
    .int()
    .min(1)
    .max(60)
    .default(15),
  APPLE_BILLING_ROOT_CA_CERTIFICATES_BASE64: z.string().default(""),
  APPLE_CHALLENGE_TTL_SECONDS: z.coerce.number().int().min(60).max(900).default(300),
  APPLE_CLIENT_IDS: z.string().default(""),
  APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64: optionalSecret,
  APPLE_CREDENTIAL_KEY_VERSION: optionalSecret,
  APPLE_JWKS_URL: z.url().default("https://appleid.apple.com/auth/keys"),
  APPLE_KEY_ID: optionalSecret,
  APPLE_PRIVATE_KEY_BASE64: optionalSecret,
  APPLE_REDIRECT_URI: optionalSecret.pipe(z.url().optional()),
  APPLE_REVOCATION_ENDPOINT: z.url().default("https://appleid.apple.com/auth/revoke"),
  APPLE_TEAM_ID: optionalSecret,
  APPLE_TOKEN_ENDPOINT: z.url().default("https://appleid.apple.com/auth/token"),
  AI_RETRY_MAX_ATTEMPTS: z.coerce.number().int().min(1).max(3).default(2),
  AI_DEEPSEEK_ALLOWED_MODELS: z.string().default("deepseek-v4-flash"),
  AI_GUEST_ACCESS_ENABLED: booleanFromString.default(false),
  AI_USAGE_RETENTION_DAYS: z.coerce.number().int().min(30).max(730).default(90),
  AI_USER_MINUTE_LIMIT: z.coerce.number().int().min(1).max(300).default(30),
  ACCOUNT_DELETION_GRACE_DAYS: z.coerce.number().int().min(1).max(30).default(7),
  ACCOUNT_DELETION_RECEIPT_RETENTION_DAYS: z.coerce
    .number()
    .int()
    .min(365)
    .max(3650)
    .default(2555),
  AUDIT_RETENTION_DAYS: z.coerce.number().int().min(30).max(2555).default(365),
  AUTH_ACCESS_TOKEN_TTL_SECONDS: z.coerce.number().int().min(60).max(3600).default(900),
  AUTH_ACTION_TOKEN_TTL_SECONDS: z.coerce
    .number()
    .int()
    .min(300)
    .max(86_400)
    .default(3600),
  AUTH_EMAIL_ACCOUNT_HOUR_LIMIT: z.coerce.number().int().min(1).max(100).default(5),
  AUTH_EMAIL_IP_HOUR_LIMIT: z.coerce.number().int().min(1).max(1_000).default(30),
  AUTH_ACTION_URL_BASE: z.url().default("http://localhost:3000/auth"),
  AUTH_AUDIENCE: z.string().trim().min(1).default("lingotrip-clients"),
  AUTH_EMAIL_FROM: z
    .string()
    .trim()
    .min(3)
    .default("LingoTrip <no-reply@local.lingotrip>"),
  AUTH_ISSUER: z.url().default("https://rplearn.haruyuki.cn"),
  AUTH_LOGIN_ACCOUNT_15M_LIMIT: z.coerce.number().int().min(1).max(100).default(10),
  AUTH_LOGIN_IP_15M_LIMIT: z.coerce.number().int().min(1).max(1_000).default(60),
  AUTH_JWT_KEY_ID: optionalSecret,
  AUTH_JWT_PRIVATE_KEY_BASE64: optionalSecret,
  AUTH_JWT_PUBLIC_KEY_BASE64: optionalSecret,
  AUTH_JWT_PREVIOUS_PUBLIC_KEYS: z.string().default(""),
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
  HTTP_GLOBAL_IP_MINUTE_LIMIT: z.coerce
    .number()
    .int()
    .min(10)
    .max(100_000)
    .default(3_000),
  JOB_LEASE_SECONDS: z.coerce.number().int().min(15).max(900).default(60),
  JOB_PAYLOAD_ENCRYPTION_KEY_BASE64: optionalSecret,
  JOB_PAYLOAD_KEY_VERSION: optionalSecret,
  JOB_PAYLOAD_PREVIOUS_KEYS: z.string().default(""),
  JOB_POLL_INTERVAL_MS: z.coerce.number().int().min(100).max(60_000).default(1000),
  JOB_RETENTION_DAYS: z.coerce.number().int().min(1).max(90).default(14),
  JOB_RETRY_BASE_SECONDS: z.coerce.number().int().min(1).max(3600).default(30),
  LOG_LEVEL: z
    .enum(["fatal", "error", "warn", "info", "debug", "trace", "silent"])
    .default("info"),
  METRICS_BEARER_TOKEN: optionalSecret,
  METRICS_ENABLED: booleanFromString.default(true),
  MEDIA_DOWNLOAD_URL_TTL_SECONDS: z.coerce.number().int().min(60).max(900).default(300),
  MEDIA_MAX_VOICE_BYTES: z.coerce
    .number()
    .int()
    .min(1024)
    .max(50 * 1024 * 1024)
    .default(20 * 1024 * 1024),
  MEDIA_PENDING_TTL_HOURS: z.coerce.number().int().min(1).max(168).default(24),
  MEDIA_RECORD_RETENTION_DAYS: z.coerce.number().int().min(1).max(365).default(30),
  MEDIA_S3_ACCESS_KEY_ID: optionalSecret,
  MEDIA_S3_BUCKET: optionalSecret,
  MEDIA_S3_ENDPOINT: optionalSecret.pipe(z.url().optional()),
  MEDIA_S3_FORCE_PATH_STYLE: booleanFromString.default(false),
  MEDIA_S3_REGION: z.string().trim().min(1).default("us-east-1"),
  MEDIA_S3_SECRET_ACCESS_KEY: optionalSecret,
  MEDIA_STORAGE_ENABLED: booleanFromString.default(false),
  MEDIA_UPLOAD_URL_TTL_SECONDS: z.coerce.number().int().min(60).max(900).default(300),
  MEDIA_USER_ASSET_LIMIT: z.coerce.number().int().min(100).max(100_000).default(10_000),
  MEDIA_USER_STORAGE_BYTES: z.coerce
    .number()
    .int()
    .min(1024 * 1024)
    .max(100 * 1024 * 1024 * 1024)
    .default(1024 * 1024 * 1024),
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

export type DatabaseConnectionConfig = Readonly<{
  databaseConnectTimeoutMs: number;
  databaseIdleTimeoutMs: number;
  databaseMaxConnections: number;
  databaseUrl: string;
  shutdownGraceMs: number;
}>;

export type RuntimeConfig = Readonly<{
  adminApiEnabled: boolean;
  adminApiKeys: readonly Readonly<{ keyId: string; token: string }>[];
  accountDeletionGraceDays: number;
  accountDeletionReceiptRetentionDays: number;
  aiRetryMaxAttempts: number;
  aiDeepSeekAllowedModels: readonly string[];
  aiGuestAccessEnabled: boolean;
  aiUsageRetentionDays: number;
  aiUserMinuteLimit: number;
  auditRetentionDays: number;
  appleAuthEnabled: boolean;
  appleBillingAppAppleId?: number;
  appleBillingBundleId: string;
  appleBillingEnabled: boolean;
  appleBillingEnableOnlineChecks: boolean;
  appleBillingIssuerId?: string;
  appleBillingKeyId?: string;
  appleBillingPrivateKeyBase64?: string;
  appleBillingReconcileActiveHours: number;
  appleBillingReconcileBatchSize: number;
  appleBillingReconcileInactiveHours: number;
  appleBillingReconcileRetryMinutes: number;
  appleBillingRootCaCertificates: readonly Buffer[];
  appleChallengeTtlSeconds: number;
  appleClientIds: readonly string[];
  appleCredentialEncryptionKeyBase64?: string;
  appleCredentialKeyVersion?: string;
  appleJwksUrl: string;
  appleKeyId?: string;
  applePrivateKeyBase64?: string;
  appleRedirectUri?: string;
  appleRevocationEndpoint: string;
  appleTeamId?: string;
  appleTokenEndpoint: string;
  authAccessTokenTtlSeconds: number;
  authActionTokenTtlSeconds: number;
  authEmailAccountHourLimit: number;
  authEmailIpHourLimit: number;
  authActionUrlBase: string;
  authAudience: string;
  authEmailFrom: string;
  authIssuer: string;
  authLoginAccount15MinuteLimit: number;
  authLoginIp15MinuteLimit: number;
  authJwtKeyId?: string;
  authJwtPrivateKeyBase64?: string;
  authJwtPublicKeyBase64?: string;
  authJwtPreviousPublicKeys: readonly Readonly<{
    keyId: string;
    publicKeyBase64: string;
  }>[];
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
  httpGlobalIpMinuteLimit: number;
  jobLeaseSeconds: number;
  jobPayloadEncryptionKeyBase64: string;
  jobPayloadKeyVersion: string;
  jobPayloadPreviousKeys: readonly Readonly<{
    keyBase64: string;
    keyVersion: string;
  }>[];
  jobPollIntervalMs: number;
  jobRetentionDays: number;
  jobRetryBaseSeconds: number;
  logLevel: "fatal" | "error" | "warn" | "info" | "debug" | "trace" | "silent";
  metricsBearerToken?: string;
  metricsEnabled: boolean;
  mediaDownloadUrlTtlSeconds: number;
  mediaMaxVoiceBytes: number;
  mediaPendingTtlHours: number;
  mediaRecordRetentionDays: number;
  mediaS3AccessKeyId?: string;
  mediaS3Bucket: string;
  mediaS3Endpoint?: string;
  mediaS3ForcePathStyle: boolean;
  mediaS3Region: string;
  mediaS3SecretAccessKey?: string;
  mediaStorageEnabled: boolean;
  mediaUploadUrlTtlSeconds: number;
  mediaUserAssetLimit: number;
  mediaUserStorageBytes: number;
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

const DEVELOPMENT_DATABASE_URL = "postgres://127.0.0.1:5432/lingotrip";
const DEVELOPMENT_REDIS_URL = "redis://127.0.0.1:6379";
const DEVELOPMENT_AUTH_PEPPER = "local-only-auth-token-pepper-change-before-production";
const DEVELOPMENT_SMTP_HOST = "127.0.0.1";

function developmentJobKey(pepper: string): string {
  return createHash("sha256")
    .update(`lingotrip-job-payload:${pepper}`)
    .digest("base64");
}

export class ConfigurationError extends Error {
  readonly issues: readonly string[];

  constructor(issues: readonly string[]) {
    super(`Invalid runtime configuration: ${issues.join("; ")}`);
    this.name = "ConfigurationError";
    this.issues = issues;
  }
}

const databaseEnvironmentSchema = rawEnvironmentSchema.pick({
  DATABASE_CONNECT_TIMEOUT_MS: true,
  DATABASE_IDLE_TIMEOUT_MS: true,
  DATABASE_MAX_CONNECTIONS: true,
  DATABASE_URL: true,
  NODE_ENV: true,
  SHUTDOWN_GRACE_MS: true,
});

export function loadDatabaseConnectionConfig(
  environment: NodeJS.ProcessEnv = process.env,
): DatabaseConnectionConfig {
  const result = databaseEnvironmentSchema.safeParse(environment);
  if (!result.success) {
    throw new ConfigurationError(
      result.error.issues.map(
        (issue) => `${issue.path.join(".") || "environment"}: ${issue.message}`,
      ),
    );
  }
  if (result.data.NODE_ENV === "production" && result.data.DATABASE_URL === undefined) {
    throw new ConfigurationError(["DATABASE_URL is required in production"]);
  }

  return {
    databaseConnectTimeoutMs: result.data.DATABASE_CONNECT_TIMEOUT_MS,
    databaseIdleTimeoutMs: result.data.DATABASE_IDLE_TIMEOUT_MS,
    databaseMaxConnections: result.data.DATABASE_MAX_CONNECTIONS,
    databaseUrl: result.data.DATABASE_URL ?? DEVELOPMENT_DATABASE_URL,
    shutdownGraceMs: result.data.SHUTDOWN_GRACE_MS,
  };
}

function parseOrigins(raw: string): readonly string[] {
  return raw
    .split(",")
    .map((origin) => origin.trim())
    .filter((origin) => origin.length > 0);
}

function parsePreviousJobKeys(
  raw: string,
): readonly Readonly<{ keyBase64: string; keyVersion: string }>[] {
  return raw
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0)
    .map((entry) => {
      const separator = entry.indexOf("=");
      if (separator <= 0 || separator === entry.length - 1) {
        throw new ConfigurationError([
          "JOB_PAYLOAD_PREVIOUS_KEYS entries must use version=base64 format",
        ]);
      }
      return {
        keyBase64: entry.slice(separator + 1),
        keyVersion: entry.slice(0, separator),
      };
    });
}

function parsePreviousJwtKeys(
  raw: string,
): readonly Readonly<{ keyId: string; publicKeyBase64: string }>[] {
  return raw
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0)
    .map((entry) => {
      const separator = entry.indexOf("=");
      if (separator <= 0 || separator === entry.length - 1) {
        throw new ConfigurationError([
          "AUTH_JWT_PREVIOUS_PUBLIC_KEYS entries must use key-id=base64 format",
        ]);
      }
      return {
        keyId: entry.slice(0, separator),
        publicKeyBase64: entry.slice(separator + 1),
      };
    });
}

function parseAdminApiKeys(
  raw: string,
): readonly Readonly<{ keyId: string; token: string }>[] {
  const entries = raw
    .split(",")
    .map((entry) => entry.trim())
    .filter((entry) => entry.length > 0)
    .map((entry) => {
      const separator = entry.indexOf("=");
      const keyId = entry.slice(0, separator);
      const token = entry.slice(separator + 1);
      if (
        separator <= 0 ||
        !/^[a-zA-Z0-9._-]{1,64}$/.test(keyId) ||
        token.length < 32
      ) {
        throw new ConfigurationError([
          "ADMIN_API_KEYS entries must use key-id=token with a token of at least 32 characters",
        ]);
      }
      return { keyId, token };
    });
  if (new Set(entries.map((entry) => entry.keyId)).size !== entries.length) {
    throw new ConfigurationError(["ADMIN_API_KEYS key IDs must be unique"]);
  }
  return entries;
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
  const jobPayloadPreviousKeys = parsePreviousJobKeys(
    result.data.JOB_PAYLOAD_PREVIOUS_KEYS,
  );
  const authJwtPreviousPublicKeys = parsePreviousJwtKeys(
    result.data.AUTH_JWT_PREVIOUS_PUBLIC_KEYS,
  );
  const adminApiKeys = parseAdminApiKeys(result.data.ADMIN_API_KEYS);
  const aiDeepSeekAllowedModels = parseOrigins(result.data.AI_DEEPSEEK_ALLOWED_MODELS);
  const issues: string[] = [];

  try {
    resolveTelemetrySettings(environment);
  } catch (error) {
    if (error instanceof TelemetryConfigurationError) {
      issues.push(error.message);
    } else {
      throw error;
    }
  }

  if (corsAllowedOrigins.length === 0) {
    issues.push("CORS_ALLOWED_ORIGINS must contain at least one origin");
  }

  if (result.data.ADMIN_API_ENABLED && adminApiKeys.length === 0) {
    issues.push("ADMIN_API_KEYS is required when the admin API is enabled");
  }

  if (
    aiDeepSeekAllowedModels.length === 0 ||
    aiDeepSeekAllowedModels.some(
      (model) => !/^[a-zA-Z0-9][a-zA-Z0-9._-]{1,127}$/.test(model),
    )
  ) {
    issues.push("AI_DEEPSEEK_ALLOWED_MODELS must contain valid model identifiers");
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

  const jwtKeyIds = [
    ...(result.data.AUTH_JWT_KEY_ID === undefined ? [] : [result.data.AUTH_JWT_KEY_ID]),
    ...authJwtPreviousPublicKeys.map((key) => key.keyId),
  ];
  if (new Set(jwtKeyIds).size !== jwtKeyIds.length) {
    issues.push("JWT key IDs must be unique across current and previous keys");
  }
  if (
    authJwtPreviousPublicKeys.some(
      (key) =>
        Buffer.from(key.publicKeyBase64, "base64").toString("utf8").trim().length === 0,
    )
  ) {
    issues.push("AUTH_JWT_PREVIOUS_PUBLIC_KEYS must contain valid base64 values");
  }

  if (result.data.NODE_ENV === "production" && result.data.SMTP_HOST === undefined) {
    issues.push("SMTP_HOST is required in production");
  }

  if (
    result.data.NODE_ENV === "production" &&
    (result.data.JOB_PAYLOAD_ENCRYPTION_KEY_BASE64 === undefined ||
      result.data.JOB_PAYLOAD_KEY_VERSION === undefined)
  ) {
    issues.push(
      "JOB_PAYLOAD_ENCRYPTION_KEY_BASE64 and JOB_PAYLOAD_KEY_VERSION are required in production",
    );
  }

  if (result.data.JOB_PAYLOAD_ENCRYPTION_KEY_BASE64 !== undefined) {
    const keyLength = Buffer.from(
      result.data.JOB_PAYLOAD_ENCRYPTION_KEY_BASE64,
      "base64",
    ).byteLength;
    if (keyLength !== 32) {
      issues.push("JOB_PAYLOAD_ENCRYPTION_KEY_BASE64 must decode to 32 bytes");
    }
  }

  if (
    jobPayloadPreviousKeys.some(
      (key) => Buffer.from(key.keyBase64, "base64").byteLength !== 32,
    )
  ) {
    issues.push("JOB_PAYLOAD_PREVIOUS_KEYS values must decode to 32 bytes");
  }

  const jobKeyVersions = [
    result.data.JOB_PAYLOAD_KEY_VERSION ?? "local-v1",
    ...jobPayloadPreviousKeys.map((key) => key.keyVersion),
  ];
  if (new Set(jobKeyVersions).size !== jobKeyVersions.length) {
    issues.push("Job payload key versions must be unique");
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

  if (result.data.NODE_ENV === "production" && !result.data.MEDIA_STORAGE_ENABLED) {
    issues.push("MEDIA_STORAGE_ENABLED must be true in production");
  }

  if (result.data.MEDIA_STORAGE_ENABLED && result.data.MEDIA_S3_BUCKET === undefined) {
    issues.push("MEDIA_S3_BUCKET is required when media storage is enabled");
  }

  if (
    (result.data.MEDIA_S3_ACCESS_KEY_ID === undefined) !==
    (result.data.MEDIA_S3_SECRET_ACCESS_KEY === undefined)
  ) {
    issues.push(
      "MEDIA_S3_ACCESS_KEY_ID and MEDIA_S3_SECRET_ACCESS_KEY must be provided together",
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
      appleBillingRootCaCertificates.length === 0 ||
      result.data.APPLE_BILLING_ISSUER_ID === undefined ||
      result.data.APPLE_BILLING_KEY_ID === undefined ||
      result.data.APPLE_BILLING_PRIVATE_KEY_BASE64 === undefined)
  ) {
    issues.push(
      "Apple billing requires App identity, root certificates, and App Store Server API credentials",
    );
  }

  if (
    result.data.APPLE_BILLING_ISSUER_ID !== undefined &&
    !z.uuid().safeParse(result.data.APPLE_BILLING_ISSUER_ID).success
  ) {
    issues.push("APPLE_BILLING_ISSUER_ID must be a UUID");
  }

  if (result.data.APPLE_BILLING_PRIVATE_KEY_BASE64 !== undefined) {
    const privateKey = Buffer.from(
      result.data.APPLE_BILLING_PRIVATE_KEY_BASE64,
      "base64",
    ).toString("utf8");
    if (!privateKey.includes("BEGIN PRIVATE KEY")) {
      issues.push(
        "APPLE_BILLING_PRIVATE_KEY_BASE64 must contain a base64-encoded PKCS#8 private key",
      );
    }
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
    adminApiEnabled: result.data.ADMIN_API_ENABLED,
    adminApiKeys,
    accountDeletionGraceDays: result.data.ACCOUNT_DELETION_GRACE_DAYS,
    accountDeletionReceiptRetentionDays:
      result.data.ACCOUNT_DELETION_RECEIPT_RETENTION_DAYS,
    aiRetryMaxAttempts: result.data.AI_RETRY_MAX_ATTEMPTS,
    aiDeepSeekAllowedModels,
    aiGuestAccessEnabled: result.data.AI_GUEST_ACCESS_ENABLED,
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
    ...(result.data.APPLE_BILLING_ISSUER_ID === undefined
      ? {}
      : { appleBillingIssuerId: result.data.APPLE_BILLING_ISSUER_ID }),
    ...(result.data.APPLE_BILLING_KEY_ID === undefined
      ? {}
      : { appleBillingKeyId: result.data.APPLE_BILLING_KEY_ID }),
    ...(result.data.APPLE_BILLING_PRIVATE_KEY_BASE64 === undefined
      ? {}
      : {
          appleBillingPrivateKeyBase64: result.data.APPLE_BILLING_PRIVATE_KEY_BASE64,
        }),
    appleBillingReconcileActiveHours: result.data.APPLE_BILLING_RECONCILE_ACTIVE_HOURS,
    appleBillingReconcileBatchSize: result.data.APPLE_BILLING_RECONCILE_BATCH_SIZE,
    appleBillingReconcileInactiveHours:
      result.data.APPLE_BILLING_RECONCILE_INACTIVE_HOURS,
    appleBillingReconcileRetryMinutes:
      result.data.APPLE_BILLING_RECONCILE_RETRY_MINUTES,
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
    appleRevocationEndpoint: result.data.APPLE_REVOCATION_ENDPOINT,
    ...(result.data.APPLE_TEAM_ID === undefined
      ? {}
      : { appleTeamId: result.data.APPLE_TEAM_ID }),
    appleTokenEndpoint: result.data.APPLE_TOKEN_ENDPOINT,
    authAccessTokenTtlSeconds: result.data.AUTH_ACCESS_TOKEN_TTL_SECONDS,
    authActionTokenTtlSeconds: result.data.AUTH_ACTION_TOKEN_TTL_SECONDS,
    authEmailAccountHourLimit: result.data.AUTH_EMAIL_ACCOUNT_HOUR_LIMIT,
    authEmailIpHourLimit: result.data.AUTH_EMAIL_IP_HOUR_LIMIT,
    authActionUrlBase: result.data.AUTH_ACTION_URL_BASE,
    authAudience: result.data.AUTH_AUDIENCE,
    authEmailFrom: result.data.AUTH_EMAIL_FROM,
    authIssuer: result.data.AUTH_ISSUER,
    authLoginAccount15MinuteLimit: result.data.AUTH_LOGIN_ACCOUNT_15M_LIMIT,
    authLoginIp15MinuteLimit: result.data.AUTH_LOGIN_IP_15M_LIMIT,
    ...(result.data.AUTH_JWT_KEY_ID === undefined
      ? {}
      : { authJwtKeyId: result.data.AUTH_JWT_KEY_ID }),
    ...(result.data.AUTH_JWT_PRIVATE_KEY_BASE64 === undefined
      ? {}
      : { authJwtPrivateKeyBase64: result.data.AUTH_JWT_PRIVATE_KEY_BASE64 }),
    ...(result.data.AUTH_JWT_PUBLIC_KEY_BASE64 === undefined
      ? {}
      : { authJwtPublicKeyBase64: result.data.AUTH_JWT_PUBLIC_KEY_BASE64 }),
    authJwtPreviousPublicKeys,
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
    httpGlobalIpMinuteLimit: result.data.HTTP_GLOBAL_IP_MINUTE_LIMIT,
    jobLeaseSeconds: result.data.JOB_LEASE_SECONDS,
    jobPayloadEncryptionKeyBase64:
      result.data.JOB_PAYLOAD_ENCRYPTION_KEY_BASE64 ??
      developmentJobKey(result.data.AUTH_TOKEN_HASH_PEPPER ?? DEVELOPMENT_AUTH_PEPPER),
    jobPayloadKeyVersion: result.data.JOB_PAYLOAD_KEY_VERSION ?? "local-v1",
    jobPayloadPreviousKeys,
    jobPollIntervalMs: result.data.JOB_POLL_INTERVAL_MS,
    jobRetentionDays: result.data.JOB_RETENTION_DAYS,
    jobRetryBaseSeconds: result.data.JOB_RETRY_BASE_SECONDS,
    logLevel: result.data.LOG_LEVEL,
    ...(result.data.METRICS_BEARER_TOKEN === undefined
      ? {}
      : { metricsBearerToken: result.data.METRICS_BEARER_TOKEN }),
    metricsEnabled: result.data.METRICS_ENABLED,
    mediaDownloadUrlTtlSeconds: result.data.MEDIA_DOWNLOAD_URL_TTL_SECONDS,
    mediaMaxVoiceBytes: result.data.MEDIA_MAX_VOICE_BYTES,
    mediaPendingTtlHours: result.data.MEDIA_PENDING_TTL_HOURS,
    mediaRecordRetentionDays: result.data.MEDIA_RECORD_RETENTION_DAYS,
    ...(result.data.MEDIA_S3_ACCESS_KEY_ID === undefined
      ? {}
      : { mediaS3AccessKeyId: result.data.MEDIA_S3_ACCESS_KEY_ID }),
    mediaS3Bucket: result.data.MEDIA_S3_BUCKET ?? "lingotrip-media-dev",
    ...(result.data.MEDIA_S3_ENDPOINT === undefined
      ? {}
      : { mediaS3Endpoint: result.data.MEDIA_S3_ENDPOINT }),
    mediaS3ForcePathStyle: result.data.MEDIA_S3_FORCE_PATH_STYLE,
    mediaS3Region: result.data.MEDIA_S3_REGION,
    ...(result.data.MEDIA_S3_SECRET_ACCESS_KEY === undefined
      ? {}
      : { mediaS3SecretAccessKey: result.data.MEDIA_S3_SECRET_ACCESS_KEY }),
    mediaStorageEnabled: result.data.MEDIA_STORAGE_ENABLED,
    mediaUploadUrlTtlSeconds: result.data.MEDIA_UPLOAD_URL_TTL_SECONDS,
    mediaUserAssetLimit: result.data.MEDIA_USER_ASSET_LIMIT,
    mediaUserStorageBytes: result.data.MEDIA_USER_STORAGE_BYTES,
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
