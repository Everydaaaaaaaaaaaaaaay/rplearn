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
      record("old-assistant", {
        role: "assistant",
        text: "That old private address is saved",
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
  it("marks pending recorded voice inputs while keeping transcript text unchanged", () => {
    const history = [
      record("old-voice", { role: "user", kind: "voice", text: "Yesterday" }),
      record("voice", {
        role: "user",
        kind: "voice",
        text: "Could we meet by the river?",
      }),
      record("text", { role: "user", kind: "text", text: "Tomorrow?" }),
    ];
    const prompt = conversationPrompt(persona, [], history, ["voice", "text"], {});
    expect(prompt[0]?.content).toContain("you have listened");
    expect(prompt[0]?.content).toContain("Do not invent these details");
    expect(prompt[0]?.content).toContain('"pendingVoiceMessageIds":["voice"]');
    expect(prompt.at(-2)?.content).toBe("Could we meet by the river?");
    expect(prompt.at(-1)?.content).toBe("Tomorrow?");
    const next = conversationPrompt(persona, [], history, ["text"], {});
    expect(next[0]?.content).not.toContain("you have listened");
    const call = conversationPrompt(persona, [], history, ["voice"], {}, true);
    expect(call[0]?.content).not.toContain("recorded voice messages");
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

describe("restored context parity", () => {
  it.each([
    ["free", 12],
    ["plus", 24],
    ["pro", 40],
  ] as const)(
    "uses %s history without truncating complete messages",
    (subscriptionTier, count) => {
      const history = Array.from({ length: 45 }, (_, i) =>
        record(`m${i.toString()}`, {
          role: i % 2 ? "assistant" : "user",
          text: `opening-${i.toString()} ` + "x".repeat(900),
        }),
      );
      const prompt = conversationPrompt(persona, [], history, ["m44"], {
        subscriptionTier,
      });
      expect(prompt).toHaveLength(count + 1);
      expect(prompt[1]?.content).toContain(`opening-${(45 - count).toString()}`);
      expect(prompt.at(-1)?.content).toHaveLength(911);
    },
  );
  it("retrieves an older relevant archived memory ahead of unrelated important facts", () => {
    const memories = Array.from({ length: 20 }, (_, i) =>
      record(`n${i.toString()}`, {
        content: `Likes unrelated ${i.toString()}`,
        importance: 5,
        tier: "long",
      }),
    );
    memories.push(
      record("relevant", {
        content:
          '@lingotrip-memory-v2:{"key":"family","text":"My sister lives in Bristol","archived":true}',
        importance: 1,
        tier: "long",
      }),
    );
    const prompt = conversationPrompt(
      persona,
      memories,
      [record("q", { role: "user", text: "Where does my sister live?" })],
      ["q"],
      {},
    );
    expect(prompt[0]?.content).toContain("My sister lives in Bristol");
  });
  it("resolves semantic ID hints against owned eligible facts and honors forgetting", () => {
    const memories = [
      record("semantic", {
        content:
          '@lingotrip-memory-v2:{"key":"family","text":"My sibling moved to Bristol","archived":true}',
        tier: "long",
      }),
      record("forgotten", {
        content:
          '@lingotrip-memory-v2:{"key":"secret","text":"erased private fact","forgotten":true}',
        tier: "long",
      }),
    ];
    const prompt = conversationPrompt(
      persona,
      memories,
      [
        record("q", {
          role: "user",
          text: "Where does my sister live?",
          createdAt: "2026-11-06T00:00:00Z",
          contextMemoryIds: ["semantic", "forgotten", "not-owned"],
        }),
      ],
      ["q"],
      {},
    );
    expect(prompt[0]?.content).toContain("My sibling moved to Bristol");
    expect(prompt[0]?.content).not.toContain("erased private fact");
  });
  it("supplies story branch, current appointments, local clock and bounded private continuity", () => {
    const character = record("ruby", {
      isMainCharacter: true,
      card: {
        name: "Ruby Walker",
        regionId: "melbourne",
        personaVoice: { flaws: ["hesitates"] },
      },
      privateNote: "USER PRIVATE NOTE",
      remarkName: "PRIVATE REMARK",
      relationship: { trust: 0.7, recentEvents: [{ reason: "INTERNAL AUDIT" }] },
      growth: {
        isPaused: true,
        arcs: [
          {
            progress: 0.2,
            trait: "patience",
            direction: "increase",
            stage: "experimenting",
          },
        ],
      },
    });
    const stories = [
      record("departures_mainline_melbourne_v2", {
        completedAt: "2026-11-05T00:00:00Z",
        flags: { "experience.RB22": true },
      }),
    ];
    const prompt = conversationPrompt(
      character,
      [],
      [record("q", { role: "user", text: "Remember our plans?" })],
      ["q"],
      { difficulty: "kindergarten" },
      false,
      {
        stories,
        appointments: [{ title: "Museum", status: "cancelled" }],
        now: new Date("2026-11-17T00:00:00Z"),
      },
    );
    expect(prompt[0]?.content).toContain("You agreed not to pick another date yet");
    expect(prompt[0]?.content).toContain('"status":"cancelled"');
    expect(prompt[0]?.content).toContain("Australia/Melbourne");
    expect(prompt[0]?.content).toContain("at most 6");
    expect(prompt[0]?.content).toContain('"isPaused":true');
    for (const secret of ["USER PRIVATE NOTE", "PRIVATE REMARK", "INTERNAL AUDIT"])
      expect(prompt[0]?.content).not.toContain(secret);
  });
  it("uses a structured memory's edit time as the privacy cutoff", () => {
    const memories = [
      record("edit", {
        createdAt: "2026-10-01T00:00:00Z",
        content:
          '@lingotrip-memory-v2:{"key":"name","text":"New name","edited":true,"observedAt":"2026-11-06T00:00:00Z"}',
      }),
    ];
    const history = [
      record("old", {
        role: "user",
        text: "Old name",
        createdAt: "2026-11-05T00:00:00Z",
      }),
      record("new", { role: "user", text: "Hello", createdAt: "2026-11-17T00:00:00Z" }),
    ];
    const prompt = conversationPrompt(persona, memories, history, ["new"], {});
    expect(JSON.stringify(prompt)).not.toContain("Old name");
    expect(JSON.stringify(prompt)).toContain("New name");
  });
});
