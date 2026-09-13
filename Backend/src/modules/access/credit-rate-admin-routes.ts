import type { FastifyInstance } from "fastify";
import type { AdminAuthenticator } from "../admin/http.js";
import type { CreditRateService } from "./credit-rate-service.js";

export function registerCreditRateAdminRoutes(
  app: FastifyInstance,
  authenticate: AdminAuthenticator,
  service: CreditRateService,
) {
  app.get(
    "/internal/admin/ai/credit-rates",
    { schema: { hide: true } },
    async (request) => {
      authenticate(request);
      return service.read();
    },
  );
  app.put(
    "/internal/admin/ai/credit-rates",
    { schema: { hide: true } },
    async (request) => {
      const operator = authenticate(request);
      return service.update(request.body, operator, request.headers["idempotency-key"]);
    },
  );
}
