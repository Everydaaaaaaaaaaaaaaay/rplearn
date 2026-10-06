import { describe, expect, it } from "vitest";
import { mainlineProgress } from "../../src/modules/domain/mainline.js";
const base = {
  starterRegionId: "london",
  hasCompletedOnboarding: true,
  completedStoryIds: [],
  isGuest: false,
};
describe("全局主线解锁政策", () => {
  it.each([
    ["london", ["london", "capetown", "newyork", "melbourne", "singapore"]],
    ["melbourne", ["melbourne", "capetown", "london", "newyork", "singapore"]],
    ["newyork", ["newyork", "capetown", "melbourne", "london", "singapore"]],
  ])("%s 起点与客户端目录保持一致", (starterRegionId, expected) => {
    const result = mainlineProgress({ ...base, starterRegionId });
    expect(result.chapters.map((chapter) => chapter.regionId)).toEqual(expected);
    expect(result.chapters.map((chapter) => chapter.state)).toEqual([
      "available",
      "locked",
      "locked",
      "locked",
      "locked",
    ]);
  });
  it("主线仅按前章推进，完成前章即可开放下一章", () => {
    expect(mainlineProgress(base).chapters[1]?.lockReason).toBe("previousChapter");
    const result = mainlineProgress({
      ...base,
      completedStoryIds: ["mainline_london"],
    });
    expect(result.chapters[1]?.state).toBe("available");
    expect(result).not.toHaveProperty("earnedStars");
    expect(result.chapters[1]).not.toHaveProperty("requiredStars");
  });
  it("保留既有已完成章，不按新门槛重新锁住", () => {
    const result = mainlineProgress({
      ...base,
      completedStoryIds: ["mainline_singapore"],
    });
    expect(result.chapters[4]).toMatchObject({ state: "completed", lockReason: null });
  });
  it("未选起点与游客限制独立生效", () => {
    expect(
      mainlineProgress({ ...base, hasCompletedOnboarding: false }).chapters[0]
        ?.lockReason,
    ).toBe("onboarding");
    const guest = mainlineProgress({
      ...base,
      isGuest: true,
      completedStoryIds: ["mainline_london"],
    });
    expect(guest.chapters[1]?.lockReason).toBe("login");
  });
});
