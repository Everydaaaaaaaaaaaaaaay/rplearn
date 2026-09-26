import { describe, expect, it } from "vitest";
import { mainlineProgress } from "../../src/modules/domain/mainline.js";
const base = {
  starterRegionId: "london",
  hasCompletedOnboarding: true,
  earnedStars: 0,
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
    expect(result.chapters.map((chapter) => chapter.requiredStars)).toEqual([
      0, 3, 9, 18, 27,
    ]);
    expect(result.chapters.map((chapter) => chapter.state)).toEqual([
      "available",
      "locked",
      "locked",
      "locked",
      "locked",
    ]);
  });
  it("星星足够仍需前章；恰好达标才开放下一章", () => {
    expect(mainlineProgress({ ...base, earnedStars: 27 }).chapters[1]?.lockReason).toBe(
      "previousChapter",
    );
    const completedStoryIds = ["mainline_london"];
    expect(
      mainlineProgress({ ...base, earnedStars: 2, completedStoryIds }).chapters[1],
    ).toMatchObject({ state: "locked", missingStars: 1, lockReason: "stars" });
    expect(
      mainlineProgress({ ...base, earnedStars: 3, completedStoryIds }).chapters[1]
        ?.state,
    ).toBe("available");
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
      earnedStars: 27,
      completedStoryIds: ["mainline_london"],
    });
    expect(guest.chapters[1]?.lockReason).toBe("login");
  });
});
