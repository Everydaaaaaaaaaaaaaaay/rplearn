import type { FastifyInstance } from "fastify";
import { z, type ZodType } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { MediaService } from "./service.js";

const sha256Schema = z.string().refine((value) => {
  const decoded = Buffer.from(value, "base64");
  return decoded.byteLength === 32 && decoded.toString("base64") === value;
}, "A canonical base64 SHA-256 digest is required");
const assetIdSchema = z.uuid().transform((value) => value.toLowerCase());

const reservationSchema = z
  .object({
    assetId: assetIdSchema,
    byteSize: z.number().int().positive(),
    checksumSha256: sha256Schema,
    contentType: z.string().trim().min(1).max(128),
    purpose: z.literal("voice_message"),
  })
  .strict();

const assetParametersSchema = z.object({
  assetId: assetIdSchema,
});

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

export function registerMediaRoutes(
  app: FastifyInstance,
  authService: AuthService,
  mediaService: MediaService,
): void {
  app.post(
    "/v1/media/assets",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["media"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const input = parse(reservationSchema, request.body);
      reply.header("cache-control", "no-store");
      return mediaService.reserveUpload(identity.userId, input);
    },
  );

  app.post(
    "/v1/media/assets/:assetId/complete",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["media"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const parameters = parse(assetParametersSchema, request.params);
      reply.header("cache-control", "no-store");
      return mediaService.completeUpload(identity.userId, parameters.assetId);
    },
  );

  app.get(
    "/v1/media/assets/:assetId",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["media"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const parameters = parse(assetParametersSchema, request.params);
      reply.header("cache-control", "no-store");
      return mediaService.createDownload(identity.userId, parameters.assetId);
    },
  );

  app.delete(
    "/v1/media/assets/:assetId",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["media"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const parameters = parse(assetParametersSchema, request.params);
      await mediaService.deleteAsset(identity.userId, parameters.assetId);
      return reply.status(204).send();
    },
  );
}
