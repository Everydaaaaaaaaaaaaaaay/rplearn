import { randomBytes } from "node:crypto";
import { exportPKCS8, generateKeyPair } from "jose";
import { afterEach, describe, expect, it, vi } from "vitest";
import { loadConfig } from "../../../../src/config/env.js";
import { createAppleCodeExchanger } from "../../../../src/modules/auth/apple/code-exchanger.js";

describe("Apple authorization code exchange", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("uses a signed client secret and the authorization_code grant", async () => {
    const keys = await generateKeyPair("ES256", { extractable: true });
    const privateKey = await exportPKCS8(keys.privateKey);
    const config = loadConfig({
      APPLE_AUTH_ENABLED: "true",
      APPLE_CLIENT_IDS: "com.example.app",
      APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64: randomBytes(32).toString("base64"),
      APPLE_CREDENTIAL_KEY_VERSION: "test-v1",
      APPLE_KEY_ID: "APPLEKEY1",
      APPLE_PRIVATE_KEY_BASE64: Buffer.from(privateKey).toString("base64"),
      APPLE_TEAM_ID: "TEAMID1234",
      NODE_ENV: "test",
    });
    const fetchStub: typeof fetch = (_input, init) => {
      expect(init?.method).toBe("POST");
      expect(init?.body).toBeInstanceOf(URLSearchParams);
      if (!(init?.body instanceof URLSearchParams)) {
        throw new Error("Expected form body");
      }
      expect(init.body.get("client_id")).toBe("com.example.app");
      expect(init.body.get("code")).toBe("single-use-code");
      expect(init.body.get("grant_type")).toBe("authorization_code");
      expect(init.body.get("client_secret")).toBeTypeOf("string");

      return Promise.resolve(
        new Response(
          JSON.stringify({
            access_token: "access",
            expires_in: 3600,
            id_token: "id-token",
            refresh_token: "refresh-token",
            token_type: "bearer",
          }),
          {
            headers: { "content-type": "application/json" },
            status: 200,
          },
        ),
      );
    };
    vi.stubGlobal("fetch", fetchStub);

    const exchanger = await createAppleCodeExchanger(config);

    await expect(
      exchanger.exchange("single-use-code", "com.example.app"),
    ).resolves.toEqual({
      idToken: "id-token",
      refreshToken: "refresh-token",
    });
  });
});
