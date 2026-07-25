import { createHmac } from "node:crypto";
import type { FastifyInstance, FastifyRequest } from "fastify";
import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import { newEntityId } from "../../shared/id.js";

const MUTATING_METHODS = new Set(["DELETE", "PATCH", "POST", "PUT"]);
const SKIPPED_ROUTES = new Set(["/health/live", "/health/ready", "/internal/metrics"]);

function actorKind(request: FastifyRequest, route: string): string {
  if (request.authUserId !== null) {
    return "user";
  }
  if (route === "/v1/billing/apple/notifications") {
    return "provider";
  }
  return "anonymous";
}

function outcome(statusCode: number): string {
  if (statusCode < 400) {
    return "success";
  }
  return statusCode < 500 ? "client_error" : "server_error";
}

export function registerAuditHooks(
  app: FastifyInstance,
  config: RuntimeConfig,
  database: DatabaseResource,
): void {
  app.addHook("onResponse", async (request, reply) => {
    const route = request.routeOptions.url ?? "unmatched";
    if (
      !MUTATING_METHODS.has(request.method) ||
      SKIPPED_ROUTES.has(route) ||
      route.startsWith("/docs/")
    ) {
      return;
    }
    const ipHash = createHmac("sha256", config.authTokenHashPepper)
      .update(`audit-ip:${request.ip}`)
      .digest("hex");
    try {
      await database.sql`
        insert into app.audit_events (
          id,
          actor_kind,
          actor_user_id,
          action,
          target_type,
          target_id,
          outcome,
          request_id,
          ip_hash,
          metadata
        )
        values (
          ${newEntityId()},
          ${actorKind(request, route)},
          ${request.authUserId},
          ${`${request.method} ${route}`},
          'http_route',
          ${route},
          ${outcome(reply.statusCode)},
          ${request.id},
          ${ipHash},
          ${JSON.stringify({ statusCode: reply.statusCode })}::jsonb
        )
      `;
    } catch (error) {
      request.log.error(
        {
          errorName: error instanceof Error ? error.name : "UnknownError",
        },
        "Audit event persistence failed",
      );
    }
  });
}
