import { randomInt } from "node:crypto";

export const MAINLINE_REWARD = { minimum: 120, maximum: 180 } as const;
export const CITY_REWARD = { minimum: 100, maximum: 130 } as const;
const mainline = new Set([
  "mainline_london",
  "mainline_melbourne",
  "mainline_newyork",
  "mainline_capetown",
  "mainline_singapore",
]);
const cities = new Set([
  "mainline_london_2",
  "mainline_melbourne_2",
  "mainline_newyork_2",
  ...[
    "capetown",
    "singapore",
    "dublin",
    "edinburgh",
    "vancouver",
    "auckland",
    "nairobi",
    "toronto",
    "sydney",
    "neworleans",
    "manchester",
    "kingston",
  ].map((city) => `city_${city}`),
]);
export function storyRewardRange(id: string) {
  return mainline.has(id) ? MAINLINE_REWARD : cities.has(id) ? CITY_REWARD : undefined;
}
// The repository persists the first award and command receipt atomically; retries cannot farm a new roll.
export function rollStoryReward(id: string): number | undefined {
  const range = storyRewardRange(id);
  return range && randomInt(range.minimum, range.maximum + 1);
}
