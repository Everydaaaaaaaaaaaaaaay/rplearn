import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { GrammarService } from "./service.js";

export function registerGrammarRoutes(
  app: FastifyInstance,
  auth: AuthService,
  service: GrammarService,
) {
  app.get("/v1/grammar/catalog", async (_request, reply) => {
    reply.header("cache-control", "public, max-age=300");
    return service.catalog();
  });
  app.post("/v1/grammar/analysis", async (request) => {
    const { userId } = await authenticateRequest(request, auth);
    const parsed = z
      .object({
        sentence: z.string().trim().min(1).max(3000),
        learnerLevel: z.string().trim().min(1).max(100),
        operationId: z.uuid(),
      })
      .strict()
      .safeParse(request.body);
    if (!parsed.success)
      throw new AppError({
        code: "INVALID_REQUEST",
        message: "Invalid grammar request.",
        statusCode: 400,
      });
    return service.analyze(userId, parsed.data);
  });
}
