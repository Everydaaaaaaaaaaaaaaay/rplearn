import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import type { DictionaryExampleCatalogService } from "./catalog-service.js";

export function registerDictionaryExampleCatalogRoutes(
  app: FastifyInstance,
  service: DictionaryExampleCatalogService,
): void {
  app.get("/v1/dictionary/learner-examples/:lemma", async (request, reply) => {
    const params = z
      .object({
        lemma: z
          .string()
          .min(1)
          .max(120)
          .regex(/^[a-zA-Z'-]+$/),
      })
      .safeParse(request.params);
    if (!params.success)
      throw new AppError({
        code: "INVALID_REQUEST",
        message: "Invalid dictionary lemma.",
        statusCode: 400,
      });
    reply.header("cache-control", "no-store");
    return { examples: await service.find(params.data.lemma) };
  });
}
