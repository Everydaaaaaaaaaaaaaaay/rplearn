import { trace, type SpanContext } from "@opentelemetry/api";
import { stdSerializers, type LoggerOptions } from "pino";
import { sanitizedTelemetryPath } from "../config/telemetry.js";

const REDACTED = "[REDACTED]";

export const SENSITIVE_LOG_PATHS = [
  "accessToken",
  "adminApiKeys",
  "adminApiKeys[*].token",
  "apiKey",
  "appleCredentialEncryptionKeyBase64",
  "appleBillingPrivateKeyBase64",
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
  activeSpanContext: () => SpanContext | undefined = () =>
    trace.getActiveSpan()?.spanContext(),
): LoggerOptions {
  return {
    level,
    mixin: () => {
      const spanContext = activeSpanContext();
      return spanContext === undefined
        ? {}
        : {
            spanId: spanContext.spanId,
            traceId: spanContext.traceId,
          };
    },
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
          url:
            serialized.url === undefined
              ? undefined
              : sanitizedTelemetryPath(serialized.url),
        };
      },
      res: (response: unknown) => {
        // Fastify 可能传入 Reply，直接读取状态码，避免 Node 序列化器误判。
        const value = response as {
          statusCode?: number;
          raw?: { statusCode?: number };
        };
        return { statusCode: value.statusCode ?? value.raw?.statusCode };
      },
    },
  };
}
