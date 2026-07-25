import { createRemoteJWKSet, jwtVerify } from "jose";
import { z } from "zod";
import type { RuntimeConfig } from "../../../config/env.js";

const appleBooleanSchema = z
  .union([z.boolean(), z.enum(["true", "false"])])
  .transform((value) => value === true || value === "true");

const appleClaimsSchema = z.object({
  aud: z.union([z.string(), z.array(z.string()).min(1)]),
  email: z.string().optional(),
  email_verified: appleBooleanSchema.optional(),
  is_private_email: appleBooleanSchema.optional(),
  nonce: z.string().optional(),
  real_user_status: z.number().int().min(0).max(2).optional(),
  sub: z.string().min(1).max(255),
});

export type AppleIdentity = Readonly<{
  audience: string;
  email?: string;
  emailVerified: boolean;
  isPrivateEmail: boolean;
  nonce?: string;
  realUserStatus?: number;
  subject: string;
}>;

export type AppleIdentityVerifier = Readonly<{
  verify: (identityToken: string, expectedNonce?: string) => Promise<AppleIdentity>;
}>;

export function createAppleIdentityVerifier(
  config: RuntimeConfig,
): AppleIdentityVerifier {
  const jwks = createRemoteJWKSet(new URL(config.appleJwksUrl), {
    cooldownDuration: 30_000,
    timeoutDuration: 5000,
  });

  return {
    verify: async (identityToken, expectedNonce) => {
      const result = await jwtVerify(identityToken, jwks, {
        algorithms: ["RS256", "ES256"],
        audience: [...config.appleClientIds],
        issuer: "https://appleid.apple.com",
      });
      const claims = appleClaimsSchema.parse(result.payload);
      if (expectedNonce !== undefined && claims.nonce !== expectedNonce) {
        throw new Error("Apple nonce mismatch");
      }

      const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
      const audience = audiences.find((value) => config.appleClientIds.includes(value));
      if (audience === undefined) {
        throw new Error("Apple audience mismatch");
      }

      return {
        audience,
        ...(claims.email === undefined ? {} : { email: claims.email }),
        emailVerified: claims.email_verified ?? false,
        isPrivateEmail: claims.is_private_email ?? false,
        ...(claims.nonce === undefined ? {} : { nonce: claims.nonce }),
        ...(claims.real_user_status === undefined
          ? {}
          : { realUserStatus: claims.real_user_status }),
        subject: claims.sub,
      };
    },
  };
}
