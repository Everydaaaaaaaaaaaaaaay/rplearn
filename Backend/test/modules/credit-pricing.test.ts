import { describe, expect, it } from "vitest";
import {
  creditPrice,
  decimalUnits,
  exactCreditCost,
  loadCreditPriceBook,
  reservationCost,
} from "../../src/modules/access/credit-pricing.js";
const book = loadCreditPriceBook();
const peak = creditPrice(
  book,
  "deepseek",
  "deepseek-v4-flash",
  new Date("2026-09-07T01:00:00Z"),
);
describe("exact credit pricing", () => {
  it("separately bills cache hit, cache miss and output without rounding drift", () => {
    const usage = {
      inputTokens: 5000,
      cacheHitTokens: 4000,
      cacheMissTokens: 1000,
      outputTokens: 500,
      totalTokens: 5500,
    };
    expect(exactCreditCost(peak, usage)).toBe(7_900_000n);
    const off = creditPrice(
      book,
      "deepseek",
      "deepseek-v4-flash",
      new Date("2026-09-07T04:00:00Z"),
    );
    expect(exactCreditCost(off, usage)).toBe(3_950_000n);
    const tiny = {
      inputTokens: 1,
      cacheHitTokens: 1,
      cacheMissTokens: 0,
      outputTokens: 0,
      totalTokens: 1,
    };
    expect(exactCreditCost(off, tiny)).toBe(50n);
    expect(
      Array.from({ length: 1000 }, () => exactCreditCost(off, tiny) ?? 0n).reduce(
        (a, b) => a + b,
        0n,
      ),
    ).toBe(50_000n);
  });
  it("does not treat missing or inconsistent usage as zero", () => {
    expect(exactCreditCost(peak, null)).toBeNull();
    expect(
      exactCreditCost(peak, { inputTokens: 5, outputTokens: 1, totalTokens: 6 }),
    ).toBeNull();
    expect(
      exactCreditCost(peak, {
        inputTokens: 5,
        outputTokens: 1,
        totalTokens: 6,
        cacheHitTokens: 6,
        cacheMissTokens: 0,
      }),
    ).toBeNull();
    expect(
      exactCreditCost(peak, {
        inputTokens: 5,
        outputTokens: 1,
        totalTokens: 7,
        cacheHitTokens: 5,
        cacheMissTokens: 0,
      }),
    ).toBeNull();
  });
  it("keeps a realistic fresh-account first chat inside the 100-credit free budget", () => {
    const messages = [
      { role: "system" as const, content: "x".repeat(24_000) },
      { role: "assistant" as const, content: "Hey, how was your trip here?" },
      { role: "user" as const, content: "I must say pretty good" },
    ];
    const mainReplyHold = reservationCost(peak, messages, 120);
    const freeDailyBudget = 100_000_000n;

    expect(mainReplyHold).toBeLessThan(freeDailyBudget);
    // A large background relationship review can make both holds exceed the budget;
    // the client therefore must not start it before the user-visible conversation.
    const backgroundReviewHold = reservationCost(
      peak,
      [{ role: "system", content: "x".repeat(12_000) }],
      1_000,
    );
    expect(mainReplyHold + backgroundReviewHold).toBeGreaterThan(freeDailyBudget);
  });
  it("rejects unknown and historical prices and excessive precision", () => {
    expect(() => creditPrice(book, "other", "deepseek-v4-flash", new Date())).toThrow();
    expect(() =>
      creditPrice(book, "deepseek", "deepseek-v4-flash", new Date("2026-01-01")),
    ).toThrow();
    expect(() => decimalUnits("0.0000000001", 9)).toThrow();
    expect(decimalUnits("0.1", 9)).toBe(100_000_000n);
  });
});
