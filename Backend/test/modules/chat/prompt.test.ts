import { describe, expect, it } from "vitest";
import { conversationPrompt } from "../../../src/modules/chat/prompt.js";
import type { ContentRecord } from "../../../src/modules/content/types.js";

function record(id: string, payload: unknown): ContentRecord {
  return {
    resourceType: "message",
    resourceId: id,
    parentId: "conversation",
    payload,
    createdAt: "2026-11-05T00:00:00Z",
    updatedAt: "2026-11-05T00:00:00Z",
    deletedAt: null,
    version: 1,
  };
}
const persona = record("character", { card: { name: "Friend", regionId: "london" } });

describe("shared conversation prompt", () => {
  it("does not reintroduce forgotten facts through old summaries or message history", () => {
    const memories = [
      record("summary", {
        content: "A secret old address",
        createdAt: "2026-11-01T00:00:00Z",
      }),
      record("forgotten", {
        content: '@lingotrip-memory-v2:{"key":"address","text":"","forgotten":true}',
        createdAt: "2026-11-04T00:00:00Z",
      }),
    ];
    const history = [
      record("old", {
        role: "user",
        text: "My old private address",
        createdAt: "2026-11-01T00:00:00Z",
      }),
      record("new", {
        role: "user",
        text: "Let's talk about today",
        createdAt: "2026-11-05T00:00:00Z",
      }),
    ];
    const prompt = conversationPrompt(persona, memories, history, ["new"], {});
    expect(JSON.stringify(prompt)).not.toContain("old address");
    expect(JSON.stringify(prompt)).not.toContain("old private address");
    expect(prompt.at(-1)?.content).toBe("Let's talk about today");
  });
  it("keeps every pending input even when more than one message is coalesced", () => {
    const ids = Array.from({ length: 20 }, (_, i) => `message-${i.toString()}`);
    const prompt = conversationPrompt(
      persona,
      [],
      ids.map((id) => record(id, { role: "user", text: id })),
      ids,
      {},
    );
    expect(prompt.filter((m) => m.role === "user").map((m) => m.content)).toEqual(ids);
  });
  it("uses the explicit voice contract for call input", () => {
    const prompt = conversationPrompt(
      persona,
      [],
      [record("input", { role: "user", text: "Hello" })],
      ["input"],
      {},
      true,
    );
    expect(prompt[0]?.content).toContain("real-time voice call");
    expect(prompt[0]?.content).toContain("45 words");
  });
});
