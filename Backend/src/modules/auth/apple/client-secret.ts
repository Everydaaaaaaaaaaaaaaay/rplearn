import { importPKCS8, SignJWT } from "jose";
import type { RuntimeConfig } from "../../../config/env.js";

export type AppleClientSecretFactory = (clientId: string) => Promise<string>;

export async function createAppleClientSecretFactory(
  config: RuntimeConfig,
): Promise<AppleClientSecretFactory> {
  if (
    config.applePrivateKeyBase64 === undefined ||
    config.appleKeyId === undefined ||
    config.appleTeamId === undefined
  ) {
    throw new Error("Apple developer credentials are not configured");
  }

  const keyId = config.appleKeyId;
  const teamId = config.appleTeamId;
  const privateKey = await importPKCS8(
    Buffer.from(config.applePrivateKeyBase64, "base64").toString("utf8"),
    "ES256",
  );

  return async (clientId) => {
    const issuedAt = Math.floor(Date.now() / 1000);
    return new SignJWT({})
      .setProtectedHeader({
        alg: "ES256",
        kid: keyId,
      })
      .setIssuer(teamId)
      .setSubject(clientId)
      .setAudience("https://appleid.apple.com")
      .setIssuedAt(issuedAt)
      .setExpirationTime(issuedAt + 5 * 60)
      .sign(privateKey);
  };
}
