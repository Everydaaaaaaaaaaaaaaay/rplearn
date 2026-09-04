import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import type { AdminAuthenticator } from "../admin/http.js";
import { dictionaryExampleRequestSchema } from "./routes.js";
import type { DictionaryTranslationService } from "./service.js";

const importItemSchema = dictionaryExampleRequestSchema
  .omit({ requestId: true })
  .extend({
    contextualMeaningZhHans: z.string().trim().min(1).max(80),
    promptVersion: z.string().trim().min(1).max(128),
    selectedMeaningIndex: z.number().int().min(0).max(23).optional(),
    sentenceZhHans: z.string().trim().min(1).max(1_000),
    translationModelVersion: z.string().trim().min(1).max(128),
  })
  .strict();

const importSchema = z
  .object({
    items: z.array(importItemSchema).min(1).max(100),
  })
  .strict();

function parse<T>(schema: ZodType<T>, value: unknown): T {
  const result = schema.safeParse(value);
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

export function registerDictionaryTranslationAdminRoutes(
  app: FastifyInstance,
  authenticateAdmin: AdminAuthenticator,
  service: DictionaryTranslationService,
): void {
  app.post(
    "/internal/admin/dictionary/example-translations/import",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["admin", "dictionary"],
      },
    },
    async (request, reply) => {
      authenticateAdmin(request);
      const body = parse(importSchema, request.body);
      reply.header("cache-control", "no-store");
      return { results: await service.importTrusted(body.items) };
    },
  );
}
