import type { LoggerOptions } from "pino";

const REDACTED = "[REDACTED]";

export const SENSITIVE_LOG_PATHS = [
  "accessToken",
  "apiKey",
  "authorization",
  "cookie",
  "deepSeekApiKey",
  "password",
  "refreshToken",
  "secret",
  "token",
  "req.headers.authorization",
  "req.headers.cookie",
  "req.body.accessToken",
  "req.body.apiKey",
  "req.body.authorization",
  "req.body.password",
  "req.body.refreshToken",
  "req.body.secret",
  "req.body.token",
  "res.headers.set-cookie",
] as const;

export function createLoggerOptions(
  level: NonNullable<LoggerOptions["level"]>,
): LoggerOptions {
  return {
    level,
    redact: {
      censor: REDACTED,
      paths: [...SENSITIVE_LOG_PATHS],
    },
  };
}
