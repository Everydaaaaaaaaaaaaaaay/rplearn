import type { FastifyInstance } from "fastify";
import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import { authenticateRequest } from "../auth/http.js";
import type { AuthService } from "../auth/service.js";
import type { AccountService } from "./service.js";

const scheduleSchema = z.object({
  confirmation: z.literal("DELETE"),
  mode: z.enum(["grace_period", "immediate"]),
});
const cancellationSchema = z.object({
  token: z.string().min(32).max(1024),
});
const unlinkSchema = z.object({ confirmation: z.literal("UNLINK") });
const identityParametersSchema = z.object({ identityId: z.uuid() });

function invalidRequest(details: unknown): AppError {
  return new AppError({
    code: "INVALID_REQUEST",
    details,
    message: "The request is invalid.",
    statusCode: 400,
  });
}

export function registerAccountRoutes(
  app: FastifyInstance,
  authService: AuthService,
  accountService: AccountService,
): void {
  app.get(
    "/v1/account/identities",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["account"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const identities = await accountService.listIdentities(identity.userId);
      reply.header("cache-control", "no-store");
      return {
        identities: identities.map((linked) => ({
          ...linked,
          createdAt: linked.createdAt.toISOString(),
          updatedAt: linked.updatedAt.toISOString(),
        })),
      };
    },
  );

  app.delete(
    "/v1/account/identities/:identityId",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["account"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const parameters = identityParametersSchema.safeParse(request.params);
      const body = unlinkSchema.safeParse(request.body);
      if (!parameters.success || !body.success) {
        throw invalidRequest([
          ...(parameters.success ? [] : parameters.error.issues),
          ...(body.success ? [] : body.error.issues),
        ]);
      }
      await accountService.unlinkIdentity(identity, parameters.data.identityId);
      return reply.status(204).send();
    },
  );

  app.get(
    "/v1/account/export",
    {
      schema: {
        security: [{ bearerAuth: [] }],
        tags: ["account"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const exported = await accountService.exportData(identity.userId);
      reply.header("cache-control", "no-store");
      reply.header(
        "content-disposition",
        `attachment; filename="lingotrip-data-${exported.generatedAt.slice(0, 10)}.json"`,
      );
      return exported;
    },
  );

  app.delete(
    "/v1/account",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: {
            confirmation: { const: "DELETE", type: "string" },
            mode: {
              enum: ["grace_period", "immediate"],
              type: "string",
            },
          },
          required: ["confirmation", "mode"],
          type: "object",
        },
        security: [{ bearerAuth: [] }],
        tags: ["account"],
      },
    },
    async (request, reply) => {
      const identity = await authenticateRequest(request, authService);
      const parsed = scheduleSchema.safeParse(request.body);
      if (!parsed.success) {
        throw invalidRequest(parsed.error.issues);
      }
      const receipt = await accountService.scheduleDeletion(
        identity.userId,
        parsed.data.mode,
      );
      return reply.status(202).send({
        cancellationToken: receipt.cancellationToken,
        purgeAt: receipt.purgeAt.toISOString(),
        requestId: receipt.requestId,
        status: "scheduled",
      });
    },
  );

  app.post(
    "/v1/account/deletion/cancel",
    {
      schema: {
        body: {
          additionalProperties: false,
          properties: {
            token: { maxLength: 1024, minLength: 32, type: "string" },
          },
          required: ["token"],
          type: "object",
        },
        tags: ["account"],
      },
    },
    async (request, reply) => {
      const parsed = cancellationSchema.safeParse(request.body);
      if (!parsed.success) {
        throw invalidRequest(parsed.error.issues);
      }
      await accountService.cancelDeletion(parsed.data.token);
      return reply.status(204).send();
    },
  );
}
