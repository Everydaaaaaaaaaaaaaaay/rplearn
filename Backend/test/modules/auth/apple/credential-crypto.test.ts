import { randomBytes } from "node:crypto";
import { describe, expect, it } from "vitest";
import { loadConfig } from "../../../../src/config/env.js";
import { createCredentialSealer } from "../../../../src/modules/auth/apple/credential-crypto.js";

describe("Apple credential encryption", () => {
  it("uses authenticated encryption with a unique nonce", () => {
    const config = loadConfig({
      APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64: randomBytes(32).toString("base64"),
      APPLE_CREDENTIAL_KEY_VERSION: "test-v1",
      NODE_ENV: "test",
    });
    const sealer = createCredentialSealer(config);
    const first = sealer.seal("refresh-token");
    const second = sealer.seal("refresh-token");

    expect(first.keyVersion).toBe("test-v1");
    expect(first.nonce).toHaveLength(12);
    expect(first.tag).toHaveLength(16);
    expect(first.ciphertext.equals(Buffer.from("refresh-token"))).toBe(false);
    expect(first.nonce.equals(second.nonce)).toBe(false);
    expect(first.ciphertext.equals(second.ciphertext)).toBe(false);
  });
});
