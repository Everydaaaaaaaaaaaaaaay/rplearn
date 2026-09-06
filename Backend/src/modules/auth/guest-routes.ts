import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import type { GuestService } from "./guest-service.js";
import type { AuthService } from "./service.js";
import { authenticateRequest } from "./http.js";

const sessionBody = z
  .object({
    installationKey: z.string().regex(/^[a-zA-Z0-9_-]{64,128}$/),
    device: z
      .object({
        deviceId: z.string().min(1).max(128),
        platform: z.enum(["ios", "android", "web", "macos", "unknown"]),
      })
      .strict(),
  })
  .strict();

export function registerGuestRoutes(
  app: FastifyInstance,
  auth: AuthService,
  guests: GuestService,
  claim: (key: string, accountId: string) => Promise<{ claimed: boolean }>,
): void {
  app.post("/v1/auth/guest", { schema: { tags: ["auth"] } }, async (request, reply) => {
    const parsed = sessionBody.safeParse(request.body);
    if (!parsed.success)
      throw new AppError({
        code: "INVALID_REQUEST",
        message: "A valid installation credential is required.",
        statusCode: 400,
      });
    reply.header("cache-control", "no-store");
    return guests.session(
      parsed.data.installationKey,
      parsed.data.device,
      auth.createRequestMetadata(request.ip, request.headers["user-agent"]),
    );
  });
  app.post(
    "/v1/auth/guest/claim",
    { schema: { tags: ["auth"] } },
    async (request, reply) => {
      const identity = await authenticateRequest(request, auth);
      const parsed = sessionBody
        .pick({ installationKey: true })
        .safeParse(request.body);
      if (!parsed.success)
        throw new AppError({
          code: "INVALID_REQUEST",
          message: "A valid installation credential is required.",
          statusCode: 400,
        });
      reply.header("cache-control", "no-store");
      return claim(parsed.data.installationKey, identity.userId);
    },
  );
}
