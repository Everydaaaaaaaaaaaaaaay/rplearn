import { describe, expect, it } from "vitest";
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
});
