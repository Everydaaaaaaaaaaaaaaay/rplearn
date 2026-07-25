import type { FastifyInstance } from "fastify";
import { checkReadiness, type ReadinessCheck } from "./readiness.js";

export function registerHealthRoutes(
  app: FastifyInstance,
  readinessChecks: readonly ReadinessCheck[],
  timeoutMs: number,
): void {
  app.get(
    "/health/live",
    {
      schema: {
        response: {
          200: {
            type: "object",
            additionalProperties: false,
            required: ["status"],
            properties: {
              status: { const: "ok", type: "string" },
            },
          },
        },
      },
    },
    () => ({ status: "ok" as const }),
  );

  app.get<{
    Reply:
      | { status: "ready" }
      | {
          checks: readonly {
            name: string;
            status: "available" | "unavailable";
          }[];
          status: "unavailable";
        };
  }>(
    "/health/ready",
    {
      schema: {
        response: {
          200: {
            type: "object",
            additionalProperties: false,
            required: ["status"],
            properties: {
              status: { const: "ready", type: "string" },
            },
          },
          503: {
            type: "object",
            additionalProperties: false,
            required: ["checks", "status"],
            properties: {
              checks: {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: ["name", "status"],
                  properties: {
                    name: { type: "string" },
                    status: {
                      enum: ["available", "unavailable"],
                      type: "string",
                    },
                  },
                },
              },
              status: { const: "unavailable", type: "string" },
            },
          },
        },
      },
    },
    async (_request, reply) => {
      const checks = await checkReadiness(readinessChecks, timeoutMs);

      if (checks.some((check) => check.status === "unavailable")) {
        return reply.status(503).send({
          checks,
          status: "unavailable",
        });
      }

      return { status: "ready" };
    },
  );
}
