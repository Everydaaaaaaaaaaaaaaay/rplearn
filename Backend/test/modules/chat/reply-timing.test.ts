import { describe, expect, it } from "vitest";
import type { ContentRecord } from "../../../src/modules/content/types.js";
import {
  handoffAt,
  generationEligibleAt,
  quietWindow,
  replyPlan,
  typingDuration,
  visiblePhase,
  type ReplySimulation,
} from "../../../src/modules/chat/reply-timing.js";

const now = Date.parse("2026-09-03T11:00:00Z");
const id = "4f4a0464-8c15-43d7-9dfb-30b98df72673";
function character(metAt: number = now): ContentRecord {
  return {
    resourceType: "character",
    resourceId: "00000000-0000-4000-8000-000000000001",
    parentId: null,
    payload: {
      metAt: new Date(metAt).toISOString(),
      card: { regionId: "london", occupation: "writer" },
    },
    createdAt: new Date(now).toISOString(),
    updatedAt: new Date(now).toISOString(),
    version: 1,
    deletedAt: null,
  };
}
const message = {
  resourceId: id,
  payload: { role: "user", createdAt: new Date(now).toISOString(), orderIndex: 1 },
};
function simulation(): ReplySimulation {
  return {
    plan: replyPlan(character(), message, [], now),
    quietUntil: now + 8000,
    resumeTypingAt: now + 8000,
    composers: {},
  };
}
describe("realistic shared reply timing", () => {
  it("matches the persisted Swift attention-policy fixture exactly", () => {
    expect(replyPlan(character(), message, [], now)).toMatchObject({
      attention: "focused",
      noticedAt: now,
      generationStartsAt: now + 1200,
      typingStartsAt: now + 4027.807,
      firstBubbleAt: now + 6138.114,
      continuingConversation: false,
    });
  });
  it("does not let an edit or blur wake an offline character early", () => {
    const value = simulation();
    value.plan.generationStartsAt = now + 120_000;
    value.preparationMilliseconds = 3000;
    value.composers.a = { sequence: 1, until: now + 25_000 };
    expect(generationEligibleAt(value)).toBe(now + 120_000);
    value.composers.a = { sequence: 2, until: now + 5000 };
    expect(generationEligibleAt(value)).toBe(now + 120_000);
  });
  it("matches Swift city, rhythm and daylight-saving presence fixtures", () => {
    const cases = [
      ["Europe/London", "daytime", "2026-09-03T11:00:00Z", "offline"],
      ["Europe/London", "daytime", "2026-03-29T10:00:00Z", "online"],
      ["America/New_York", "nightOwl", "2026-11-01T10:00:00Z", "offline"],
      ["Australia/Melbourne", "earlyBird", "2026-10-04T03:00:00Z", "online"],
      ["Africa/Nairobi", "irregular", "2026-09-03T01:00:00Z", "offline"],
    ] as const;
    for (const [zone, rhythm, timestamp, expected] of cases) {
      const date = Date.parse(timestamp);
      const npc = {
        ...character(),
        resourceId: "a2cc58c1-602b-41b5-8d99-90a18d732227",
        payload: {
          metAt: new Date(date - 30 * 86400_000).toISOString(),
          card: {
            activityProfile: {
              timeZoneIdentifier: zone,
              rhythm,
              focusDurationMinutes: 7,
            },
          },
        },
      };
      const input = {
        ...message,
        payload: { ...message.payload, createdAt: timestamp },
      };
      expect(replyPlan(npc, input, [], date).attention).toBe(expected);
    }
  });
  it("keeps focus for seven minutes and expires it", () => {
    const prior = (seconds: number) => ({
      resourceId: "assistant",
      payload: {
        role: "assistant",
        orderIndex: 0,
        createdAt: new Date(now - seconds * 1000).toISOString(),
      },
    });
    const active = replyPlan(character(now - 86400_000), message, [prior(419)], now);
    expect(active.continuingConversation).toBe(true);
    expect(active.typingStartsAt - now).toBeGreaterThanOrEqual(3000);
    expect(active.typingStartsAt - now).toBeLessThanOrEqual(4000);
    expect(
      replyPlan(character(now - 86400_000), message, [prior(421)], now)
        .continuingConversation,
    ).toBe(false);
  });
  it("restores quiet windows and natural ten-word typing pace", () => {
    expect(quietWindow("Hello there", 1, false)).toBe(8090);
    expect(quietWindow("Hello there", 1, true)).toBe(3090);
    expect(quietWindow("because", 3, false)).toBe(9000);
    expect(typingDuration("One two three four five six seven eight nine ten", 0)).toBe(
      6450,
    );
    expect(typingDuration("One two three four five six seven eight nine ten", 1)).toBe(
      6700,
    );
  });
  it("uses every device's live lease and never treats model generation as typing", () => {
    const value = simulation();
    expect(visiblePhase(value, "queued", now)).toBe("yielding");
    expect(visiblePhase(value, "dispatched", now + 7000)).toBe("yielding");
    expect(visiblePhase(value, "dispatched", now + 9000)).toBe("typing");
    value.composers.a = { sequence: 1, until: now + 25_000 };
    value.composers.b = { sequence: 1, until: now + 30_000 };
    expect(handoffAt(value)).toBe(now + 30_000);
    value.composers.a.until = 0;
    expect(visiblePhase(value, "dispatched", now + 26_000)).toBe("yielding");
    expect(visiblePhase(value, "dispatched", now + 31_000)).toBe("typing");
  });
  it("keeps schedule and personality deterministic across cities, dates and restarts", () => {
    for (const regionId of ["london", "melbourne", "newyork", "nairobi"]) {
      const npc = character(now - 86400_000);
      (npc.payload as { card: { regionId: string } }).card.regionId = regionId;
      for (const date of [
        now,
        Date.parse("2026-03-29T10:00:00Z"),
        Date.parse("2026-11-01T10:00:00Z"),
      ]) {
        const input = {
          ...message,
          payload: { ...message.payload, createdAt: new Date(date).toISOString() },
        };
        const plan = replyPlan(npc, input, [], date);
        expect(plan).toEqual(replyPlan(npc, input, [], date));
        expect(plan.generationStartsAt).toBeGreaterThanOrEqual(plan.noticedAt);
        expect(plan.generationStartsAt).toBeLessThanOrEqual(plan.typingStartsAt);
        expect(plan.typingStartsAt).toBeLessThan(plan.firstBubbleAt);
      }
    }
  });
});
