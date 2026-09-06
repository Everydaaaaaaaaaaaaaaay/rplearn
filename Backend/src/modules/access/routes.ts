import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { authenticateActorRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import { AppError } from "../../shared/errors.js";
import type { AccessService } from "./service.js";
export function registerAccessRoutes(
  app: FastifyInstance,
  auth: AuthService,
  service: AccessService,
): void {
  app.get("/v1/access", async (request, reply) => {
    reply.header("cache-control", "no-store");
    return service.snapshot((await authenticateActorRequest(request, auth)).userId);
  });
  app.post("/v1/access/voice", async (request) => {
    const identity = await authenticateActorRequest(request, auth);
    const parsed = z.object({ operationId: z.uuid() }).safeParse(request.body);
    if (!parsed.success)
      throw new AppError({
        code: "INVALID_REQUEST",
        message: "A voice operation ID is required.",
        statusCode: 400,
      });
    return service.reserve(
      identity.userId,
      parsed.data.operationId,
      "voice-v1",
      "voice",
      60,
    );
  });
  app.post("/v1/access/voice/stop", async (request) => {
    const identity = await authenticateActorRequest(request, auth);
    const parsed = z.object({ operationId: z.uuid() }).safeParse(request.body);
    if (!parsed.success)
      throw new AppError({
        code: "INVALID_REQUEST",
        message: "A voice operation ID is required.",
        statusCode: 400,
      });
    // Never accept client-supplied seconds or refunds. Server elapsed time is authoritative.
    await service.stopVoice(identity.userId, parsed.data.operationId);
    return service.snapshot(identity.userId);
  });
}
