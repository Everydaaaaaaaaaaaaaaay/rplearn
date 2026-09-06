import { createHmac, randomBytes } from "node:crypto";
import {
  generateKeyPair,
  exportJWK,
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
  jwks: Readonly<{
    keys: readonly Readonly<Record<string, unknown>>[];
  }>;
  verifyAccessToken: (token: string) => Promise<AccessIdentity>;
}>;

async function loadSigningKeys(config: RuntimeConfig): Promise<
  Readonly<{
    currentKeyId: string;
    currentPrivateKey: CryptoKey;
    verificationKeys: ReadonlyMap<string, CryptoKey>;
  }>
> {
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

    const currentKeyId = config.authJwtKeyId ?? "configured-without-key-id";
    const currentPrivateKey = await importPKCS8(privatePem, "EdDSA");
    const currentPublicKey = await importSPKI(publicPem, "EdDSA");
    const verificationKeys = new Map<string, CryptoKey>([
      [currentKeyId, currentPublicKey],
    ]);
    for (const previous of config.authJwtPreviousPublicKeys) {
      const previousPem = Buffer.from(previous.publicKeyBase64, "base64").toString(
        "utf8",
      );
      verificationKeys.set(previous.keyId, await importSPKI(previousPem, "EdDSA"));
    }
    const probe = await new SignJWT({ probe: true })
      .setProtectedHeader({ alg: "EdDSA", kid: currentKeyId })
      .sign(currentPrivateKey);
    await jwtVerify(probe, currentPublicKey, { algorithms: ["EdDSA"] });
    return {
      currentKeyId,
      currentPrivateKey,
      verificationKeys,
    };
  }

  const generated = await generateKeyPair("EdDSA");
  return {
    currentKeyId: "development-ephemeral",
    currentPrivateKey: generated.privateKey,
    verificationKeys: new Map([["development-ephemeral", generated.publicKey]]),
  };
}

export async function createAuthTokenService(
  config: RuntimeConfig,
): Promise<AuthTokenService> {
  const keys = await loadSigningKeys(config);
  const publicJwks = await Promise.all(
    [...keys.verificationKeys.entries()].map(async ([keyId, key]) => ({
      ...(await exportJWK(key)),
      alg: "EdDSA",
      kid: keyId,
      use: "sig",
    })),
  );

  return {
    accessTokenTtlSeconds: config.authAccessTokenTtlSeconds,
    createAccessToken: async (identity) => {
      const issuedAt = Math.floor(Date.now() / 1000);
      return new SignJWT({
        scope: [identity.isGuest === true ? "guest" : "user"],
        sid: identity.sessionId,
        tv: identity.tokenVersion,
      })
        .setProtectedHeader({
          alg: "EdDSA",
          kid: keys.currentKeyId,
          typ: "at+jwt",
        })
        .setSubject(identity.userId)
        .setIssuer(config.authIssuer)
        .setAudience(config.authAudience)
        .setJti(newEntityId())
        .setIssuedAt(issuedAt)
        .setExpirationTime(issuedAt + config.authAccessTokenTtlSeconds)
        .sign(keys.currentPrivateKey);
    },
    createOpaqueToken: () => randomBytes(48).toString("base64url"),
    hashOpaqueValue: (value) =>
      createHmac("sha256", config.authTokenHashPepper).update(value).digest("hex"),
    jwks: { keys: publicJwks },
    verifyAccessToken: async (token) => {
      const result = await jwtVerify(
        token,
        (protectedHeader) => {
          if (protectedHeader.alg !== "EdDSA" || protectedHeader.kid === undefined) {
            throw new Error("A known EdDSA key ID is required");
          }
          const key = keys.verificationKeys.get(protectedHeader.kid);
          if (key === undefined) {
            throw new Error("The JWT key ID is not active");
          }
          return key;
        },
        {
          algorithms: ["EdDSA"],
          audience: config.authAudience,
          issuer: config.authIssuer,
        },
      );

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
