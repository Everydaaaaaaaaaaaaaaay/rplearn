import type { FastifyError, FastifyInstance } from "fastify";
import { AppError, type PublicErrorBody } from "../shared/errors.js";

function isValidationError(error: FastifyError): boolean {
  return error.validation !== undefined;
}

export function registerErrorHandling(app: FastifyInstance): void {
  app.setNotFoundHandler((request, reply) => {
    const body: PublicErrorBody = {
      code: "ROUTE_NOT_FOUND",
      message: "The requested resource does not exist.",
      requestId: request.id,
    };

    return reply.status(404).send(body);
  });

  app.setErrorHandler((error: FastifyError, request, reply) => {
    if (isValidationError(error)) {
      const body: PublicErrorBody = {
        code: "INVALID_REQUEST",
        details: error.validation,
        message: "The request is invalid.",
        requestId: request.id,
      };

      return reply.status(400).send(body);
    }

    if (error instanceof AppError) {
      if (error.statusCode >= 500) {
        request.log.error({ err: error }, "Operational request failure");
      }

      const body: PublicErrorBody = {
        code: error.code,
        message: error.expose ? error.message : "An unexpected error occurred.",
        requestId: request.id,
        ...(error.expose && error.details !== undefined
          ? { details: error.details }
          : {}),
      };

      return reply.status(error.statusCode).send(body);
    }

    request.log.error({ err: error }, "Unhandled request failure");

    const body: PublicErrorBody = {
      code: "INTERNAL_ERROR",
      message: "An unexpected error occurred.",
      requestId: request.id,
    };

    return reply.status(500).send(body);
  });
}
