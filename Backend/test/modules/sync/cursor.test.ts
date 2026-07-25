import { describe, expect, it } from "vitest";
import { createSyncCursorCodec } from "../../../src/modules/sync/cursor.js";

describe("sync cursor codec", () => {
  const codec = createSyncCursorCodec("test-sync-cursor-secret");
  const userId = "019c0123-4567-789a-8bcd-ef0123456789";

  it("round-trips a user-bound sequence", () => {
    const cursor = codec.encode(userId, "90071992547409930");

    expect(codec.decode(cursor, userId)).toBe("90071992547409930");
  });

  it("rejects tampering and use by another user", () => {
    const cursor = codec.encode(userId, "42");
    const tampered = `${cursor.slice(0, -1)}${cursor.endsWith("a") ? "b" : "a"}`;

    expect(() => codec.decode(tampered, userId)).toThrow(
      expect.objectContaining({ code: "INVALID_SYNC_CURSOR" }),
    );
    expect(() => codec.decode(cursor, "019c0123-4567-789a-8bcd-ef0123456790")).toThrow(
      expect.objectContaining({ code: "INVALID_SYNC_CURSOR" }),
    );
  });
});
