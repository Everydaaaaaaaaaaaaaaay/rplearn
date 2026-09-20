import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateActorRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { DictionaryExampleGenerationService } from "./generation-service.js";
import type { DictionaryExampleCatalogService } from "./catalog-service.js";

export function registerDictionaryExampleCatalogRoutes(
  app: FastifyInstance,
  service: DictionaryExampleCatalogService,
  options?: { generation: DictionaryExampleGenerationService; auth: AuthService },
): void {
  app.get("/v1/dictionary/learner-examples/:lemma", async (request, reply) => {
    const params = z
      .object({
        lemma: z
          .string()
          .min(1)
          .max(120)
          .regex(/^[a-zA-Z][a-zA-Z' -]*$/),
      })
      .safeParse(request.params);
    if (!params.success)
      throw new AppError({
        code: "INVALID_REQUEST",
        message: "Invalid dictionary lemma.",
        statusCode: 400,
      });
    reply.header("cache-control", "no-store");
    return options === undefined
      ? { examples: await service.find(params.data.lemma) }
      : options.generation.resolve(params.data.lemma);
  });
  if (options !== undefined)
    app.post("/v1/dictionary/learner-examples/resolve", async (request, reply) => {
      const body = z
        .object({
          lemma: z
            .string()
            .trim()
            .min(1)
            .max(120)
            .regex(/^[a-zA-Z][a-zA-Z' -]*$/),
          generateOnMiss: z.boolean().default(false),
        })
        .strict()
        .safeParse(request.body);
      if (!body.success)
        throw new AppError({
          code: "INVALID_REQUEST",
          message: "Invalid dictionary example request.",
          statusCode: 400,
        });
      const userId = body.data.generateOnMiss
        ? (await authenticateActorRequest(request, options.auth)).userId
        : undefined;
      reply.header("cache-control", "no-store");
      return options.generation.resolve(body.data.lemma, userId);
    });
}
