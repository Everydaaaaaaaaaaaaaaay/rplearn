import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import { AppError } from "../../shared/errors.js";
import type { LearningService } from "./service.js";
const schema = z.object({
  revision: z.number().int().min(0).max(2_147_483_646),
  payload: z.string(),
});
export function registerLearningRoutes(
  app: FastifyInstance,
  auth: AuthService,
  service: LearningService,
): void {
  app.get("/v1/learning/state", async (request, reply) => {
    const identity = await authenticateRequest(request, auth);
    reply.header("cache-control", "no-store");
    return service.read(identity.userId);
  });
  app.put("/v1/learning/state", { bodyLimit: 4_194_304 }, async (request, reply) => {
    const identity = await authenticateRequest(request, auth);
    const parsed = schema.safeParse(request.body);
    if (!parsed.success)
      throw new AppError({
        code: "INVALID_REQUEST",
        message: "Invalid learning sync request.",
        statusCode: 400,
      });
    reply.header("cache-control", "no-store");
    return service.save(identity.userId, parsed.data.revision, parsed.data.payload);
  });
}
