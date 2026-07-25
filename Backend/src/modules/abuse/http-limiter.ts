import type { FastifyInstance, FastifyRequest } from "fastify";
import { createHmac } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import type { RedisResource } from "../../infrastructure/redis/client.js";
import { AppError } from "../../shared/errors.js";

type LimitRule = Readonly<{
  key: string;
  limit: number;
  windowSeconds: number;
}>;

const EMAIL_ACTIONS = new Set([
  "/v1/auth/email/resend",
  "/v1/auth/password/forgot",
  "/v1/auth/register",
]);
const LOGIN_ACTIONS = new Set(["/v1/auth/apple/login", "/v1/auth/login"]);
const TOKEN_ACTIONS = new Set([
  "/v1/auth/email/verify",
  "/v1/auth/password/reset",
  "/v1/auth/refresh",
]);

function bodyEmail(request: FastifyRequest): string | undefined {
  if (
    typeof request.body !== "object" ||
    request.body === null ||
    !("email" in request.body)
  ) {
    return undefined;
  }
  const value = (request.body as { email?: unknown }).email;
  return typeof value === "string" ? value.trim().toLowerCase() : undefined;
}

export function registerHttpAbuseProtection(
  app: FastifyInstance,
  config: RuntimeConfig,
  redis: RedisResource,
): void {
  const reference = (namespace: string, value: string): string =>
    createHmac("sha256", config.authTokenHashPepper)
      .update(`http-abuse:${namespace}:${value}`)
      .digest("hex");
  let lastRedisWarningAt = 0;

  app.addHook("preHandler", async (request, reply) => {
    const route = request.routeOptions.url;
    if (!route?.startsWith("/v1/")) {
      return;
    }
    const ipReference = reference("ip", request.ip);
    const rules: LimitRule[] = [
      {
        key: `abuse:global:${ipReference}`,
        limit: config.httpGlobalIpMinuteLimit,
        windowSeconds: 60,
      },
    ];
    const sensitive =
      route.startsWith("/v1/auth/") || route === "/v1/account/deletion/cancel";

    if (LOGIN_ACTIONS.has(route)) {
      rules.push({
        key: `abuse:login:ip:${ipReference}`,
        limit: config.authLoginIp15MinuteLimit,
        windowSeconds: 15 * 60,
      });
      const email = bodyEmail(request);
      if (email !== undefined) {
        rules.push({
          key: `abuse:login:account:${reference("email", email)}`,
          limit: config.authLoginAccount15MinuteLimit,
          windowSeconds: 15 * 60,
        });
      }
    } else if (EMAIL_ACTIONS.has(route)) {
      rules.push({
        key: `abuse:email:ip:${ipReference}`,
        limit: config.authEmailIpHourLimit,
        windowSeconds: 60 * 60,
      });
      const email = bodyEmail(request);
      if (email !== undefined) {
        rules.push({
          key: `abuse:email:account:${reference("email", email)}`,
          limit: config.authEmailAccountHourLimit,
          windowSeconds: 60 * 60,
        });
      }
    } else if (TOKEN_ACTIONS.has(route)) {
      rules.push({
        key: `abuse:token:ip:${ipReference}`,
        limit: config.authLoginIp15MinuteLimit * 2,
        windowSeconds: 15 * 60,
      });
    } else if (route === "/v1/auth/apple/challenge") {
      rules.push({
        key: `abuse:apple-challenge:ip:${ipReference}`,
        limit: config.authEmailIpHourLimit,
        windowSeconds: 60 * 60,
      });
    }

    let results: readonly number[];
    try {
      results = await Promise.all(
        rules.map((rule) => redis.consumeFixedWindow(rule.key, rule.windowSeconds)),
      );
    } catch (error) {
      if (sensitive) {
        throw new AppError({
          cause: error,
          code: "ABUSE_PROTECTION_UNAVAILABLE",
          message: "Authentication protection is temporarily unavailable.",
          statusCode: 503,
        });
      }
      if (Date.now() - lastRedisWarningAt > 60_000) {
        lastRedisWarningAt = Date.now();
        request.log.warn(
          {
            errorName: error instanceof Error ? error.name : "UnknownError",
          },
          "HTTP abuse limiter unavailable; non-sensitive request allowed",
        );
      }
      return;
    }

    let tightest:
      | Readonly<{
          limit: number;
          remaining: number;
          windowSeconds: number;
        }>
      | undefined;
    for (const [index, count] of results.entries()) {
      const rule = rules[index];
      if (rule === undefined) {
        continue;
      }
      const remaining = Math.max(0, rule.limit - count);
      if (
        tightest === undefined ||
        remaining / rule.limit < tightest.remaining / tightest.limit
      ) {
        tightest = {
          limit: rule.limit,
          remaining,
          windowSeconds: rule.windowSeconds,
        };
      }
      if (count > rule.limit) {
        reply.header("retry-after", String(rule.windowSeconds));
        reply.header("ratelimit-limit", String(rule.limit));
        reply.header("ratelimit-remaining", "0");
        reply.header("ratelimit-reset", String(rule.windowSeconds));
        throw new AppError({
          code: "RATE_LIMIT_EXCEEDED",
          details: {
            limit: rule.limit,
            windowSeconds: rule.windowSeconds,
          },
          message: "Too many requests were submitted.",
          statusCode: 429,
        });
      }
    }
    if (tightest !== undefined) {
      reply.header("ratelimit-limit", String(tightest.limit));
      reply.header("ratelimit-remaining", String(tightest.remaining));
      reply.header("ratelimit-reset", String(tightest.windowSeconds));
    }
  });
}
