import { describe, expect, it, vi } from "vitest";
import { randomUUID } from "node:crypto";
import {
  continuityViolations,
  repeatedReply,
  replyFragments,
} from "../../../src/modules/chat/reply-quality.js";
import {
  createChatGeneration,
  createChatRecovery,
} from "../../../src/modules/chat/ai-generation.js";
import type { AiService } from "../../../src/modules/ai/service.js";
import type { ChatGenerationInput } from "../../../src/modules/chat/contracts.js";

const input = (): ChatGenerationInput => ({
  userId: randomUUID(),
  generationId: randomUUID(),
  conversationId: randomUUID(),
  characterId: randomUUID(),
  inputMessageIds: [randomUUID()],
  messages: [{ role: "user", content: "I hope this doesn't damage our friendship" }],
});
describe("shared reply quality", () => {
  it("detects repeated multi-bubble output and severe continuity failures", () => {
    expect(
      repeatedReply("That's a lovely idea. Let's go tomorrow.", [
        "That's a lovely idea.",
        "Let's go tomorrow.",
      ]),
    ).toBe(true);
    expect(
      continuityViolations(
        "We're good now.",
        "I hope this doesn't damage our friendship",
      ),
    ).toEqual(["premature_mutual_repair"]);
  });
  it("splits natural short bubbles and preserves every word past four bubbles", () => {
    const text =
      "I was going to take the train, but I think walking sounds much better.\none\ntwo\nthree\nfour\nfive";
    const fragments = replyFragments(text);
    expect(fragments).toHaveLength(4);
    expect(fragments.join(" ")).toBe(text.replace(/\s+/g, " "));
    expect(fragments[0]).toBe("I was going to take the train,");
  });
  it("uses one stable linked repair and guards a second severe violation", async () => {
    const complete = vi.fn().mockResolvedValue({ content: "We're good now." });
    const ai = {
      complete,
      operationPending: vi.fn().mockResolvedValue(false),
    } as unknown as AiService;
    const turn = input();
    const result = await createChatGeneration(ai)(turn, () => Promise.resolve());
    expect(complete).toHaveBeenCalledTimes(2);
    const repair = complete.mock.calls[1]?.[1] as {
      operationId: string;
      parentOperationId: string;
    };
    expect(repair.parentOperationId).toBe(turn.generationId);
    expect(repair.operationId).not.toBe(turn.generationId);
    expect(result).toContain("I'll respect what you asked");
    expect(turn.suppressLearning).toBe(true);
    await createChatGeneration(ai)(turn, () => Promise.resolve());
    expect((complete.mock.calls[3]?.[1] as { operationId: string }).operationId).toBe(
      repair.operationId,
    );
  });
  it("waits for an uncertain repair instead of publishing the original candidate", async () => {
    const ai = {
      completedResult: vi.fn().mockResolvedValue(null),
      operationPending: vi.fn().mockResolvedValue(true),
    } as unknown as AiService;
    expect(await createChatRecovery(ai).recover?.(input())).toBeNull();
  });
});
