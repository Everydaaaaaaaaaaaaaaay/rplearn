import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../../shared/errors.js";
import { authenticateRequest } from "../http.js";
import type { AuthService } from "../service.js";
import type { AppleAuthService, AppleAuthentication } from "./service.js";

const authenticationSchema = z.object({
  authorizationCode: z.string().min(1).max(4096),
  challengeId: z.uuid(),
  identityToken: z.string().min(1).max(16_384),
});

const deviceSchema = z.object({
  appVersion: z.string().trim().min(1).max(64).optional(),
  deviceId: z.string().trim().min(8).max(128),
  deviceName: z.string().trim().min(1).max(128).optional(),
  platform: z.enum(["ios", "android", "web", "macos", "unknown"]),
});

const loginSchema = authenticationSchema.extend({
  device: deviceSchema,
});

function parseAuthentication(value: unknown): AppleAuthentication {
  const result = authenticationSchema.safeParse(value);
  if (!result.success) {
    throw new AppError({
      code: "INVALID_REQUEST",
      message: "The request is invalid.",
      statusCode: 400,
    });
  }
  return result.data;
}

function publicTokenPair(pair: Awaited<ReturnType<AppleAuthService["login"]>>) {
  return {
    ...pair,
    refreshTokenExpiresAt: pair.refreshTokenExpiresAt.toISOString(),
  };
}

export function registerAppleAuthRoutes(
  app: FastifyInstance,
  appleService: AppleAuthService,
  authService: AuthService,
): void {
  app.post(
    "/v1/auth/apple/challenge",
    {
      schema: {
        response: {
          200: {
            additionalProperties: false,
            properties: {
              challengeId: { format: "uuid", type: "string" },
              expiresIn: { type: "integer" },
              nonce: { type: "string" },
            },
            required: ["challengeId", "expiresIn", "nonce"],
            type: "object",
          },
        },
        tags: ["auth"],
      },
    },
    () => appleService.createChallenge(),
  );

  app.post(
    "/v1/auth/apple/login",
    {
      schema: {
        tags: ["auth"],
      },
    },
    async (request) => {
      const result = loginSchema.safeParse(request.body);
      if (!result.success) {
        throw new AppError({
          code: "INVALID_REQUEST",
          message: "The request is invalid.",
          statusCode: 400,
        });
      }
      const userAgent = request.headers["user-agent"];
      const pair = await appleService.login(
        {
          authorizationCode: result.data.authorizationCode,
          challengeId: result.data.challengeId,
          identityToken: result.data.identityToken,
        },
        {
          ...(result.data.device.appVersion === undefined
            ? {}
            : { appVersion: result.data.device.appVersion }),
          deviceId: result.data.device.deviceId,
          ...(result.data.device.deviceName === undefined
            ? {}
            : { deviceName: result.data.device.deviceName }),
          platform: result.data.device.platform,
        },
        authService.createRequestMetadata(
          request.ip,
          typeof userAgent === "string" ? userAgent : undefined,
        ),
      );
      return publicTokenPair(pair);
    },
  );

  app.post(
    "/v1/auth/apple/link",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["auth"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      await appleService.link(identity, parseAuthentication(request.body));
      return reply.status(204).send();
    },
  );
}
