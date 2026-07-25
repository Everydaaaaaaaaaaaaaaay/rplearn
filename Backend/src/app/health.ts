import type { FastifyInstance } from "fastify";

export function registerHealthRoutes(app: FastifyInstance): void {
  app.get(
    "/health/live",
    {
      config: {
        rateLimit: false,
      },
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

  app.get(
    "/health/ready",
    {
      config: {
        rateLimit: false,
      },
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
        },
      },
    },
    () => ({ status: "ready" as const }),
  );
}
