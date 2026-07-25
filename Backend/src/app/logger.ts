import { stdSerializers, type LoggerOptions } from "pino";

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
  "cancellationToken",
  "jobPayloadEncryptionKeyBase64",
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
    serializers: {
      err: stdSerializers.err,
      req: (request: unknown) => {
        const serialized = stdSerializers.req(
          request as Parameters<typeof stdSerializers.req>[0],
        ) as {
          method?: string;
          remoteAddress?: string;
          remotePort?: number;
          url?: string;
        };
        return {
          method: serialized.method,
          remoteAddress: serialized.remoteAddress,
          remotePort: serialized.remotePort,
          url: serialized.url?.split("?")[0],
        };
      },
      res: (response: unknown) => {
        const serialized = stdSerializers.res(
          response as Parameters<typeof stdSerializers.res>[0],
        ) as {
          statusCode?: number;
        };
        return {
          statusCode: serialized.statusCode,
        };
      },
    },
  };
}
