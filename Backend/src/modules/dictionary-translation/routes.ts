import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { DictionaryTranslationService } from "./service.js";

const dictionaryDescriptorSchema = z
  .object({
    source: z
      .string()
      .trim()
      .min(1)
      .max(64)
      .regex(/^[A-Za-z0-9][A-Za-z0-9._-]*$/),
    version: z.string().trim().min(1).max(64),
  })
  .strict();

export const dictionaryExampleRequestSchema = z
  .object({
    candidateMeaningsZhHans: z.array(z.string().trim().min(1).max(160)).max(24),
    dictionary: dictionaryDescriptorSchema,
    lemma: z.string().trim().min(1).max(120),
    partOfSpeech: z.string().trim().min(1).max(48),
    requestId: z
      .string()
      .trim()
      .min(1)
      .max(64)
      .regex(/^[A-Za-z0-9._:-]+$/)
      .optional(),
    senseDefinitionEn: z.string().trim().min(1).max(2_000).optional(),
    sentence: z.string().trim().min(1).max(2_000),
    stableSenseId: z.string().trim().min(1).max(1_024).optional(),
  })
  .strict();

const resolveSchema = z
  .object({
    generateOnMiss: z.boolean().default(false),
    requests: z.array(dictionaryExampleRequestSchema).min(1).max(32),
  })
  .strict();

const guestDeviceIdSchema = z
  .string()
  .trim()
  .min(8)
  .max(128)
  .regex(/^[a-zA-Z0-9._:-]+$/);

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

export function registerDictionaryTranslationRoutes(
  app: FastifyInstance,
  authService: AuthService,
  service: DictionaryTranslationService,
  options: Readonly<{
    resolveGuestUser?: (deviceId: string) => Promise<string>;
  }> = {},
): void {
  app.post(
    "/v1/dictionary/example-translations/resolve",
    {
      schema: {
        security: [{ bearerAuth: [] }, {}],
        tags: ["dictionary"],
      },
    },
    async (request, reply) => {
      const body = parse(resolveSchema, request.body);
      let userId: string | undefined;
      if (request.headers.authorization !== undefined) {
        userId = (await authenticateRequest(request, authService)).userId;
      } else if (
        body.generateOnMiss &&
        options.resolveGuestUser !== undefined &&
        request.headers["x-lingotrip-guest-id"] !== undefined
      ) {
        const deviceId = parse(
          guestDeviceIdSchema,
          request.headers["x-lingotrip-guest-id"],
        );
        userId = await options.resolveGuestUser(deviceId);
        request.authUserId = userId;
      }
      reply.header("cache-control", "no-store");
      return {
        results: await service.resolve(body.requests, {
          generateOnMiss: body.generateOnMiss,
          ...(userId === undefined ? {} : { userId }),
        }),
      };
    },
  );
}
