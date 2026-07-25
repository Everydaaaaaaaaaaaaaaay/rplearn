import { describe, expect, it } from "vitest";
import { createContentCursorCodec } from "../../../src/modules/content/cursor.js";

describe("content cursor", () => {
  const codec = createContentCursorCodec("test-content-cursor-secret");
  const userId = "019c0123-4567-789a-8bcd-ef0123456789";

  it("round trips and binds the page to one account", () => {
    const cursor = codec.encode({
      lastId: "019c0123-4567-789a-8bcd-ef0123456790",
      lastType: "conversation",
      snapshotSequence: "42",
      userId,
    });
    expect(codec.decode(cursor, userId)).toEqual({
      lastId: "019c0123-4567-789a-8bcd-ef0123456790",
      lastType: "conversation",
      snapshotSequence: "42",
      userId,
      version: 1,
    });
    expect(() =>
      codec.decode(cursor, "019c0123-4567-789a-8bcd-ef0123456799"),
    ).toThrow();
  });

  it("rejects non-canonical and tampered values", () => {
    const cursor = codec.encode({
      lastId: "story_1",
      lastType: "story_progress",
      snapshotSequence: "0",
      userId,
    });
    expect(() => codec.decode(`${cursor.slice(0, -1)}x`, userId)).toThrow();
    expect(() => codec.decode(`${cursor}=`, userId)).toThrow();
  });
});
