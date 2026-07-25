import { createHmac, randomBytes } from "node:crypto";
import {
  generateKeyPair,
  importPKCS8,
  importSPKI,
  jwtVerify,
  SignJWT,
  type CryptoKey,
} from "jose";
import { z } from "zod";
import type { RuntimeConfig } from "../../config/env.js";
import { newEntityId } from "../../shared/id.js";
import type { AccessIdentity } from "./types.js";

const accessClaimsSchema = z.object({
  sid: z.uuid(),
  sub: z.uuid(),
  tv: z.number().int().nonnegative(),
});

export type AuthTokenService = Readonly<{
  accessTokenTtlSeconds: number;
  createAccessToken: (identity: AccessIdentity) => Promise<string>;
  createOpaqueToken: () => string;
  hashOpaqueValue: (value: string) => string;
  verifyAccessToken: (token: string) => Promise<AccessIdentity>;
}>;

async function loadSigningKeys(
  config: RuntimeConfig,
): Promise<Readonly<{ privateKey: CryptoKey; publicKey: CryptoKey }>> {
  if (
    config.authJwtPrivateKeyBase64 !== undefined &&
    config.authJwtPublicKeyBase64 !== undefined
  ) {
    const privatePem = Buffer.from(config.authJwtPrivateKeyBase64, "base64").toString(
      "utf8",
    );
    const publicPem = Buffer.from(config.authJwtPublicKeyBase64, "base64").toString(
      "utf8",
    );

    return {
      privateKey: await importPKCS8(privatePem, "EdDSA"),
      publicKey: await importSPKI(publicPem, "EdDSA"),
    };
  }

  return generateKeyPair("EdDSA");
}

export async function createAuthTokenService(
  config: RuntimeConfig,
): Promise<AuthTokenService> {
  const keys = await loadSigningKeys(config);
  const keyId = config.authJwtKeyId ?? "development-ephemeral";

  return {
    accessTokenTtlSeconds: config.authAccessTokenTtlSeconds,
    createAccessToken: async (identity) => {
      const issuedAt = Math.floor(Date.now() / 1000);
      return new SignJWT({
        scope: ["user"],
        sid: identity.sessionId,
        tv: identity.tokenVersion,
      })
        .setProtectedHeader({
          alg: "EdDSA",
          kid: keyId,
          typ: "at+jwt",
        })
        .setSubject(identity.userId)
        .setIssuer(config.authIssuer)
        .setAudience(config.authAudience)
        .setJti(newEntityId())
        .setIssuedAt(issuedAt)
        .setExpirationTime(issuedAt + config.authAccessTokenTtlSeconds)
        .sign(keys.privateKey);
    },
    createOpaqueToken: () => randomBytes(48).toString("base64url"),
    hashOpaqueValue: (value) =>
      createHmac("sha256", config.authTokenHashPepper).update(value).digest("hex"),
    verifyAccessToken: async (token) => {
      const result = await jwtVerify(token, keys.publicKey, {
        algorithms: ["EdDSA"],
        audience: config.authAudience,
        issuer: config.authIssuer,
      });

      if (result.protectedHeader.typ !== "at+jwt") {
        throw new Error("Unexpected token type");
      }

      const claims = accessClaimsSchema.parse(result.payload);
      return {
        sessionId: claims.sid,
        tokenVersion: claims.tv,
        userId: claims.sub,
      };
    },
  };
}
