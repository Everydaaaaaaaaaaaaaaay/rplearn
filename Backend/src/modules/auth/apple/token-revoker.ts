import type { RuntimeConfig } from "../../../config/env.js";
import { createAppleClientSecretFactory } from "./client-secret.js";

export type AppleTokenRevoker = Readonly<{
  revokeRefreshToken: (clientId: string, refreshToken: string) => Promise<void>;
}>;

export async function createAppleTokenRevoker(
  config: RuntimeConfig,
): Promise<AppleTokenRevoker> {
  const createClientSecret = await createAppleClientSecretFactory(config);

  return {
    revokeRefreshToken: async (clientId, refreshToken) => {
      const response = await fetch(config.appleRevocationEndpoint, {
        body: new URLSearchParams({
          client_id: clientId,
          client_secret: await createClientSecret(clientId),
          token: refreshToken,
          token_type_hint: "refresh_token",
        }),
        headers: {
          "content-type": "application/x-www-form-urlencoded",
        },
        method: "POST",
        signal: AbortSignal.timeout(10_000),
      });
      if (!response.ok) {
        throw new Error("AppleTokenRevocationFailed");
      }
    },
  };
}
