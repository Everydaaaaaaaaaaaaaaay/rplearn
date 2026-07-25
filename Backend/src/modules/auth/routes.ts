import type { FastifyInstance, FastifyRequest } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "./http.js";
import type { AuthService } from "./service.js";
import type { DeviceDescriptor } from "./types.js";

const emailSchema = z.email().max(254);
const passwordSchema = z.string().min(12).max(128);
const opaqueTokenSchema = z.string().min(32).max(1024);
const deviceSchema = z.object({
  appVersion: z.string().trim().min(1).max(64).optional(),
  deviceId: z.string().trim().min(8).max(128),
  deviceName: z.string().trim().min(1).max(128).optional(),
  platform: z.enum(["ios", "android", "web", "macos", "unknown"]),
});

const emailBodySchema = z.object({
  email: emailSchema,
});

const registerBodySchema = z.object({
  email: emailSchema,
  password: passwordSchema,
});

const loginBodySchema = registerBodySchema.extend({
  device: deviceSchema,
});

const tokenBodySchema = z.object({
  token: opaqueTokenSchema,
});

const resetPasswordBodySchema = z.object({
  newPassword: passwordSchema,
  token: opaqueTokenSchema,
});

const refreshBodySchema = z.object({
  refreshToken: opaqueTokenSchema,
});

const logoutBodySchema = z.object({
  allDevices: z.boolean().default(false),
});

function parseBody<T>(schema: ZodType<T>, body: unknown): T {
  const result = schema.safeParse(body);
  if (result.success) {
    return result.data;
  }

  throw new AppError({
    code: "INVALID_REQUEST",
    details: result.error.issues.map((issue) => ({
      code: issue.code,
      message: issue.message,
      path: issue.path,
    })),
    message: "The request is invalid.",
    statusCode: 400,
  });
}

function requestMetadata(request: FastifyRequest, service: AuthService) {
  const userAgent = request.headers["user-agent"];
  return service.createRequestMetadata(
    request.ip,
    typeof userAgent === "string" ? userAgent : undefined,
  );
}

function publicSession(
  session: Awaited<ReturnType<AuthService["listSessions"]>>[number],
) {
  return {
    appVersion: session.appVersion,
    createdAt: session.createdAt.toISOString(),
    current: session.current,
    deviceId: session.deviceId,
    deviceName: session.deviceName,
    id: session.id,
    lastSeenAt: session.lastSeenAt.toISOString(),
    platform: session.platform,
  };
}

const acceptedResponseSchema = {
  additionalProperties: false,
  properties: {
    status: { const: "accepted", type: "string" },
  },
  required: ["status"],
  type: "object",
} as const;

const tokenResponseSchema = {
  additionalProperties: false,
  properties: {
    accessToken: { type: "string" },
    accessTokenExpiresIn: { type: "integer" },
    refreshToken: { type: "string" },
    refreshTokenExpiresAt: { format: "date-time", type: "string" },
    sessionId: { format: "uuid", type: "string" },
    tokenType: { const: "Bearer", type: "string" },
    userId: { format: "uuid", type: "string" },
  },
  required: [
    "accessToken",
    "accessTokenExpiresIn",
    "refreshToken",
    "refreshTokenExpiresAt",
    "sessionId",
    "tokenType",
    "userId",
  ],
  type: "object",
} as const;

function publicTokenPair(pair: Awaited<ReturnType<AuthService["login"]>>) {
  return {
    ...pair,
    refreshTokenExpiresAt: pair.refreshTokenExpiresAt.toISOString(),
  };
}

export function registerAuthRoutes(app: FastifyInstance, service: AuthService): void {
  app.get(
    "/.well-known/jwks.json",
    {
      schema: {
        tags: ["auth-metadata"],
      },
    },
    (_request, reply) => {
      reply.header("cache-control", "public, max-age=300, stale-while-revalidate=300");
      return service.jwks();
    },
  );

  app.post(
    "/v1/auth/register",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: {
            email: { format: "email", maxLength: 254, type: "string" },
            password: {
              maxLength: 128,
              minLength: 12,
              type: "string",
              writeOnly: true,
            },
          },
          required: ["email", "password"],
          type: "object",
        },
        response: { 202: acceptedResponseSchema },
        tags: ["auth"],
      },
    },
    async (request, reply) => {
      const body = parseBody(registerBodySchema, request.body);
      await service.register(body.email, body.password);
      return reply.status(202).send({ status: "accepted" });
    },
  );

  app.post(
    "/v1/auth/email/verify",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: { token: { type: "string", writeOnly: true } },
          required: ["token"],
          type: "object",
        },
        tags: ["auth"],
      },
    },
    async (request, reply) => {
      const body = parseBody(tokenBodySchema, request.body);
      await service.verifyEmail(body.token);
      return reply.status(204).send();
    },
  );

  app.post(
    "/v1/auth/email/resend",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: {
            email: { format: "email", maxLength: 254, type: "string" },
          },
          required: ["email"],
          type: "object",
        },
        response: { 202: acceptedResponseSchema },
        tags: ["auth"],
      },
    },
    async (request, reply) => {
      const body = parseBody(emailBodySchema, request.body);
      await service.requestEmailVerification(body.email);
      return reply.status(202).send({ status: "accepted" });
    },
  );

  app.post(
    "/v1/auth/login",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: {
            device: {
              additionalProperties: false,
              properties: {
                appVersion: { maxLength: 64, type: "string" },
                deviceId: {
                  maxLength: 128,
                  minLength: 8,
                  type: "string",
                },
                deviceName: { maxLength: 128, type: "string" },
                platform: {
                  enum: ["ios", "android", "web", "macos", "unknown"],
                  type: "string",
                },
              },
              required: ["deviceId", "platform"],
              type: "object",
            },
            email: { format: "email", maxLength: 254, type: "string" },
            password: {
              maxLength: 128,
              minLength: 12,
              type: "string",
              writeOnly: true,
            },
          },
          required: ["device", "email", "password"],
          type: "object",
        },
        response: { 200: tokenResponseSchema },
        tags: ["auth"],
      },
    },
    async (request) => {
      const body = parseBody(loginBodySchema, request.body);
      const pair = await service.login(
        body.email,
        body.password,
        body.device as DeviceDescriptor,
        requestMetadata(request, service),
      );
      return publicTokenPair(pair);
    },
  );

  app.post(
    "/v1/auth/refresh",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: {
            refreshToken: { type: "string", writeOnly: true },
          },
          required: ["refreshToken"],
          type: "object",
        },
        response: { 200: tokenResponseSchema },
        tags: ["auth"],
      },
    },
    async (request) => {
      const body = parseBody(refreshBodySchema, request.body);
      return publicTokenPair(await service.refresh(body.refreshToken));
    },
  );

  app.post(
    "/v1/auth/password/forgot",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: {
            email: { format: "email", maxLength: 254, type: "string" },
          },
          required: ["email"],
          type: "object",
        },
        response: { 202: acceptedResponseSchema },
        tags: ["auth"],
      },
    },
    async (request, reply) => {
      const body = parseBody(emailBodySchema, request.body);
      await service.forgotPassword(body.email);
      return reply.status(202).send({ status: "accepted" });
    },
  );

  app.post(
    "/v1/auth/password/reset",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: {
            newPassword: {
              maxLength: 128,
              minLength: 12,
              type: "string",
              writeOnly: true,
            },
            token: { type: "string", writeOnly: true },
          },
          required: ["newPassword", "token"],
          type: "object",
        },
        tags: ["auth"],
      },
    },
    async (request, reply) => {
      const body = parseBody(resetPasswordBodySchema, request.body);
      await service.resetPassword(body.token, body.newPassword);
      return reply.status(204).send();
    },
  );

  app.get(
    "/v1/auth/sessions",
    {
      schema: {
        response: {
          200: {
            additionalProperties: false,
            properties: {
              sessions: {
                items: {
                  additionalProperties: false,
                  properties: {
                    appVersion: { nullable: true, type: "string" },
                    createdAt: { format: "date-time", type: "string" },
                    current: { type: "boolean" },
                    deviceId: { type: "string" },
                    deviceName: { nullable: true, type: "string" },
                    id: { format: "uuid", type: "string" },
                    lastSeenAt: { format: "date-time", type: "string" },
                    platform: { type: "string" },
                  },
                  required: [
                    "appVersion",
                    "createdAt",
                    "current",
                    "deviceId",
                    "deviceName",
                    "id",
                    "lastSeenAt",
                    "platform",
                  ],
                  type: "object",
                },
                type: "array",
              },
            },
            required: ["sessions"],
            type: "object",
          },
        },
        security: [{ bearerAuth: [] }],
        tags: ["auth"],
      },
    },
    async (request) => {
      const identity = await authenticateRequest(request, service);
      const sessions = await service.listSessions(identity);
      return { sessions: sessions.map(publicSession) };
    },
  );

  app.delete(
    "/v1/auth/sessions/:sessionId",
    {
      schema: {
        params: {
          additionalProperties: false,
          properties: {
            sessionId: { format: "uuid", type: "string" },
          },
          required: ["sessionId"],
          type: "object",
        },
        security: [{ bearerAuth: [] }],
        tags: ["auth"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, service);
      const parameters = z.object({ sessionId: z.uuid() }).parse(request.params);
      await service.revokeSession(identity, parameters.sessionId);
      return reply.status(204).send();
    },
  );

  app.post(
    "/v1/auth/logout",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: { allDevices: { default: false, type: "boolean" } },
          type: "object",
        },
        security: [{ bearerAuth: [] }],
        tags: ["auth"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, service);
      const body = parseBody(logoutBodySchema, request.body ?? {});
      if (body.allDevices) {
        await service.revokeAllSessions(identity);
      } else {
        await service.revokeSession(identity, identity.sessionId);
      }
      return reply.status(204).send();
    },
  );
}
