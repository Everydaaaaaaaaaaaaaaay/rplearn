import { describe, expect, it } from "vitest";
import { z } from "zod";
import {
  mapProfile,
  type ProfileRow,
} from "../../../src/modules/domain/repository-mappers.js";

const profileRow: ProfileRow = {
  coins: 500,
  current_region_id: "london",
  difficulty: "junior1",
  display_name: "旅行者",
  experience_points: 0,
  friend_slot_limit: 5,
  game_level: 1,
  has_completed_onboarding: false,
  has_completed_profile_setup: false,
  learning_goal: "dailyConversation",
  placement_completed_at: null,
  placement_score: null,
  proficiency_source: "selfReported",
  starter_region_id: null,
  study_stage: null,
  updated_at: "2026-10-01T00:00:00.000Z",
  version: 1,
};

// 对应移除旧小测前 iOS 的非可选 Bool 解码约束。
const legacyProfileSchema = z.object({ quizGloballyEnabled: z.boolean() });

describe("旧版客户端用户资料响应兼容", () => {
  it.each([false, true])("建档状态为 %s 时仍可解码旅程快照", (completed) => {
    const profile = mapProfile(
      {
        ...profileRow,
        has_completed_onboarding: completed,
        has_completed_profile_setup: completed,
        starter_region_id: completed ? "london" : null,
      },
      completed ? ["london"] : [],
    );
    const wire = JSON.parse(
      JSON.stringify({ cursor: "cursor", state: { profile } }),
    ) as {
      state: { profile: unknown };
    };
    expect(legacyProfileSchema.parse(wire.state.profile).quizGloballyEnabled).toBe(
      false,
    );
    expect(profile.coins).toBe(500);
    expect(profile.hasCompletedOnboarding).toBe(completed);
    expect(profile.starterRegionId).toBe(completed ? "london" : null);
    expect(profile.version).toBe(1);
  });

  it("直接资料响应保持同一兼容字段且不读取旧数据库开关", () => {
    const profile = mapProfile(
      { ...profileRow, quiz_globally_enabled: true } as ProfileRow,
      [],
    );
    expect(legacyProfileSchema.parse(JSON.parse(JSON.stringify(profile)))).toEqual({
      quizGloballyEnabled: false,
    });
    expect(profile).not.toHaveProperty("quiz_globally_enabled");
  });
});
