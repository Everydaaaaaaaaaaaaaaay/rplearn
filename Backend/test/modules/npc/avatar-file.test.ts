import { createHash } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import { verifyAvatarFile } from "../../../src/modules/npc/avatar-file.js";

describe("avatar file publication verification", () => {
  afterEach(() => vi.unstubAllGlobals());
  it("checks streamed bytes against the manifest and refuses content substitution", async () => {
    const bytes = new Uint8Array([137, 80, 78, 71, 13, 10, 26, 10, 0]);
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation(() => Promise.resolve(new Response(bytes))),
    );
    await expect(
      verifyAvatarFile(
        "https://example.com/a.png",
        createHash("sha256").update(bytes).digest("hex"),
      ),
    ).resolves.toBeUndefined();
    await expect(
      verifyAvatarFile("https://example.com/a.png", "a".repeat(64)),
    ).rejects.toThrow("SHA-256");
  });
  it("rejects non-image bytes even if the content type claims an image", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockImplementation(() =>
          Promise.resolve(
            new Response("<html>error</html>", {
              headers: { "content-type": "image/png" },
            }),
          ),
        ),
    );
    await expect(
      verifyAvatarFile("https://example.com/a.png", "a".repeat(64)),
    ).rejects.toThrow("PNG, JPEG or WebP");
  });
});
