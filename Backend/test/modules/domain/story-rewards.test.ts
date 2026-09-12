import { describe, expect, it } from "vitest";
import {
  CITY_REWARD,
  MAINLINE_REWARD,
  rollStoryReward,
} from "../../../src/modules/domain/story-rewards.js";
describe("story economy guarantee", () => {
  it("funds each ticket gate with minimum city rewards, leaving 500", () => {
    let coins = 9 * CITY_REWARD.minimum;
    expect(coins).toBeGreaterThanOrEqual(500);
    coins = coins - 500 + 3 * CITY_REWARD.minimum;
    expect(coins).toBeGreaterThanOrEqual(500);
    coins = coins - 500 + 3 * CITY_REWARD.minimum;
    expect(coins).toBe(500);
    expect(coins + 5 * MAINLINE_REWARD.minimum).toBe(1100);
  });
  it("uses correct ranges and refuses unknown stories", () => {
    for (let i = 0; i < 100; i++) {
      const city = rollStoryReward("mainline_london_2") ?? -1;
      const main = rollStoryReward("mainline_london") ?? -1;
      expect(city).toBeGreaterThanOrEqual(100);
      expect(city).toBeLessThanOrEqual(130);
      expect(main).toBeGreaterThanOrEqual(120);
      expect(main).toBeLessThanOrEqual(180);
    }
    expect(rollStoryReward("invented")).toBeUndefined();
  });
});
