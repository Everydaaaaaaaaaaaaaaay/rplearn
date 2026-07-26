import { createHash, timingSafeEqual } from "node:crypto";
import type { FastifyRequest } from "fastify";
import type { RuntimeConfig } from "../../config/env.js";
import { AppError } from "../../shared/errors.js";

type PreparedKey = Readonly<{
  hash: Buffer;
  keyId: string;
}>;

export type AdminAuthenticator = (request: FastifyRequest) => string;

function digest(value: string): Buffer {
  return createHash("sha256").update(value).digest();
}

export function createAdminAuthenticator(
  keys: RuntimeConfig["adminApiKeys"],
): AdminAuthenticator {
  const prepared: readonly PreparedKey[] = keys.map((key) => ({
    hash: digest(key.token),
    keyId: key.keyId,
  }));

  return (request) => {
    const supplied = /^Bearer ([^\s]+)$/i.exec(
      request.headers.authorization ?? "",
    )?.[1];
    const suppliedHash = digest(supplied ?? "");
    let matchedKeyId: string | undefined;
    for (const candidate of prepared) {
      if (timingSafeEqual(candidate.hash, suppliedHash)) {
        matchedKeyId = candidate.keyId;
      }
    }
    if (supplied === undefined || matchedKeyId === undefined) {
      throw new AppError({
        code: "UNAUTHORIZED",
        message: "A valid operator credential is required.",
        statusCode: 401,
      });
    }
    request.operatorKeyId = matchedKeyId;
    return matchedKeyId;
  };
}
