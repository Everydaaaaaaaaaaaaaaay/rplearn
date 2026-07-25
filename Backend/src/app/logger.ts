import type { LoggerOptions } from "pino";

const REDACTED = "[REDACTED]";

export const SENSITIVE_LOG_PATHS = [
  "accessToken",
  "apiKey",
  "appleCredentialEncryptionKeyBase64",
  "applePrivateKeyBase64",
  "authorizationCode",
  "authorization",
  "cookie",
  "deepSeekApiKey",
  "authJwtPrivateKeyBase64",
  "authTokenHashPepper",
  "password",
  "refreshToken",
  "secret",
  "smtpPassword",
  "token",
  "req.headers.authorization",
  "req.headers.cookie",
  "req.body.accessToken",
  "req.body.apiKey",
  "req.body.authorization",
  "req.body.authorizationCode",
  "req.body.identityToken",
  "req.body.messages",
  "req.body.newPassword",
  "req.body.password",
  "req.body.refreshToken",
  "req.body.secret",
  "req.body.signedPayload",
  "req.body.signedTransaction",
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
