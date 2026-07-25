import { z } from "zod";
import type { RuntimeConfig } from "../../../config/env.js";
import { AppError } from "../../../shared/errors.js";
import { createAppleClientSecretFactory } from "./client-secret.js";

const tokenResponseSchema = z.object({
  access_token: z.string().min(1),
  expires_in: z.number().int().positive(),
  id_token: z.string().min(1),
  refresh_token: z.string().min(1),
  token_type: z.string().min(1),
});

export type AppleCodeExchange = Readonly<{
  idToken: string;
  refreshToken: string;
}>;

export type AppleCodeExchanger = Readonly<{
  exchange: (authorizationCode: string, clientId: string) => Promise<AppleCodeExchange>;
}>;

export async function createAppleCodeExchanger(
  config: RuntimeConfig,
): Promise<AppleCodeExchanger> {
  const createClientSecret = await createAppleClientSecretFactory(config);

  return {
    exchange: async (authorizationCode, clientId) => {
      const form = new URLSearchParams({
        client_id: clientId,
        client_secret: await createClientSecret(clientId),
        code: authorizationCode,
        grant_type: "authorization_code",
      });
      if (config.appleRedirectUri !== undefined) {
        form.set("redirect_uri", config.appleRedirectUri);
      }

      const response = await fetch(config.appleTokenEndpoint, {
        body: form,
        headers: {
          "content-type": "application/x-www-form-urlencoded",
        },
        method: "POST",
        signal: AbortSignal.timeout(10_000),
      });

      if (!response.ok) {
        throw new AppError({
          code: "APPLE_AUTHORIZATION_REJECTED",
          message: "Apple rejected the authorization credentials.",
          statusCode: response.status >= 500 ? 502 : 401,
        });
      }

      const parsed = tokenResponseSchema.safeParse(await response.json());
      if (!parsed.success) {
        throw new AppError({
          code: "APPLE_INVALID_RESPONSE",
          expose: false,
          message: "Apple returned an invalid token response.",
          statusCode: 502,
        });
      }

      return {
        idToken: parsed.data.id_token,
        refreshToken: parsed.data.refresh_token,
      };
    },
  };
}
