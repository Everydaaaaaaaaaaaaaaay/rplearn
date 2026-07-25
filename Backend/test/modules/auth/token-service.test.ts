import { describe, expect, it } from "vitest";
import { exportPKCS8, exportSPKI, generateKeyPair } from "jose";
import { loadConfig } from "../../../src/config/env.js";
import { createAuthTokenService } from "../../../src/modules/auth/token-service.js";
import { newEntityId } from "../../../src/shared/id.js";

describe("AuthTokenService", () => {
  it("signs scoped access tokens and rejects a different key", async () => {
    const first = await createAuthTokenService(loadConfig({ NODE_ENV: "test" }));
    const second = await createAuthTokenService(loadConfig({ NODE_ENV: "test" }));
    const identity = {
      sessionId: newEntityId(),
      tokenVersion: 2,
      userId: newEntityId(),
    };

    const token = await first.createAccessToken(identity);

    await expect(first.verifyAccessToken(token)).resolves.toEqual(identity);
    await expect(second.verifyAccessToken(token)).rejects.toThrow();
  });

  it("creates high-entropy opaque tokens and keyed digests", async () => {
    const service = await createAuthTokenService(loadConfig({ NODE_ENV: "test" }));
    const token = service.createOpaqueToken();
    const digest = service.hashOpaqueValue(token);

    expect(token.length).toBeGreaterThanOrEqual(64);
    expect(digest).toMatch(/^[a-f0-9]{64}$/);
    expect(digest).not.toContain(token);
    expect(service.hashOpaqueValue(token)).toBe(digest);
  });

  it("keeps old access tokens valid during a key-ring rotation", async () => {
    const oldKeys = await keyMaterial("old-key");
    const newKeys = await keyMaterial("new-key");
    const oldService = await createAuthTokenService(
      loadConfig({
        AUTH_JWT_KEY_ID: oldKeys.keyId,
        AUTH_JWT_PRIVATE_KEY_BASE64: oldKeys.privateKey,
        AUTH_JWT_PUBLIC_KEY_BASE64: oldKeys.publicKey,
        NODE_ENV: "test",
      }),
    );
    const rotatedService = await createAuthTokenService(
      loadConfig({
        AUTH_JWT_KEY_ID: newKeys.keyId,
        AUTH_JWT_PREVIOUS_PUBLIC_KEYS: `${oldKeys.keyId}=${oldKeys.publicKey}`,
        AUTH_JWT_PRIVATE_KEY_BASE64: newKeys.privateKey,
        AUTH_JWT_PUBLIC_KEY_BASE64: newKeys.publicKey,
        NODE_ENV: "test",
      }),
    );
    const identity = {
      sessionId: newEntityId(),
      tokenVersion: 1,
      userId: newEntityId(),
    };

    const oldToken = await oldService.createAccessToken(identity);
    const newToken = await rotatedService.createAccessToken(identity);

    await expect(rotatedService.verifyAccessToken(oldToken)).resolves.toEqual(identity);
    await expect(oldService.verifyAccessToken(newToken)).rejects.toThrow();
    expect(rotatedService.jwks.keys.map((key) => key.kid).sort()).toEqual([
      "new-key",
      "old-key",
    ]);
  });
});

async function keyMaterial(keyId: string): Promise<
  Readonly<{
    keyId: string;
    privateKey: string;
    publicKey: string;
  }>
> {
  const pair = await generateKeyPair("EdDSA", { extractable: true });
  return {
    keyId,
    privateKey: Buffer.from(await exportPKCS8(pair.privateKey)).toString("base64"),
    publicKey: Buffer.from(await exportSPKI(pair.publicKey)).toString("base64"),
  };
}
