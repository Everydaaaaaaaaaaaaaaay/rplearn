import type { FastifyRequest } from "fastify";
import { AppError } from "../../shared/errors.js";
import type { AuthService } from "./service.js";
import type { AccessIdentity } from "./types.js";

export function bearerToken(request: FastifyRequest): string {
  const match = /^Bearer ([^\s]+)$/i.exec(request.headers.authorization ?? "");
  if (match?.[1] === undefined) {
    throw new AppError({
      code: "UNAUTHORIZED",
      message: "A valid access token is required.",
      statusCode: 401,
    });
  }
  return match[1];
}

export function authenticateRequest(
  request: FastifyRequest,
  authService: AuthService,
): Promise<AccessIdentity> {
  return authService.authenticate(bearerToken(request)).then((identity) => {
    request.authUserId = identity.userId;
    return identity;
  });
}
