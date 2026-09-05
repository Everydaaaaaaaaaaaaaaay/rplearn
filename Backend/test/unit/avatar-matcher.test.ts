import { describe, expect, it } from "vitest";
import {
  avatarMatches,
  chooseAvatar,
  type AvatarCandidate,
} from "../../src/modules/npc/avatar-matcher.js";
import { avatarManifestSchema } from "../../src/modules/npc/avatar-import.js";
const avatar: AvatarCandidate = {
  id: "a",
  imageUrl: "https://example.com/a.png",
  tags: ["theme:red", "facing:right"],
  profile: {
    ageMin: 25,
    ageMax: 44,
    gender: "female",
    appearance: "Short dark curls",
    styleVersion: "v4",
    sha256: "a".repeat(64),
  },
};
const request = { age: 29, gender: "female", requiredTags: [] } as const;
describe("portrait compatibility and sampling", () => {
  it("never relaxes age, gender or requested tags", () => {
    expect(avatarMatches(avatar, request)).toBe(true);
    expect(avatarMatches(avatar, { ...request, age: 45 })).toBe(false);
    expect(avatarMatches(avatar, { ...request, gender: "male" })).toBe(false);
    expect(avatarMatches(avatar, { ...request, requiredTags: ["facing:left"] })).toBe(
      false,
    );
    expect(avatarMatches({ ...avatar, profile: null, tags: [] }, request)).toBe(false);
  });
  it("considers candidates beyond 64 and distinguishes exhaustion from a coverage gap", () => {
    const candidates = Array.from({ length: 100 }, (_, i) => ({
      ...avatar,
      id: String(i),
    }));
    expect(chooseAvatar(candidates, request, new Set(), () => 99).avatar?.id).toBe(
      "99",
    );
    expect(chooseAvatar([avatar], request, new Set(["a"])).reason).toBe(
      "user_pool_exhausted",
    );
    expect(chooseAvatar([avatar], { ...request, age: 80 }, new Set()).reason).toBe(
      "coverage_gap",
    );
    expect(chooseAvatar([avatar], request, new Set()).avatar).toEqual(avatar);
    expect(() => chooseAvatar([avatar], request, new Set(), () => 1)).toThrow(
      RangeError,
    );
  });
  it("validates immutable-manifest identity and profile intervals", () => {
    const entry = {
      id: crypto.randomUUID(),
      url: avatar.imageUrl,
      tags: avatar.tags,
      profile: avatar.profile,
    };
    expect(
      avatarManifestSchema.safeParse({ version: 2, avatars: [entry] }).success,
    ).toBe(true);
    expect(
      avatarManifestSchema.safeParse({ version: 2, avatars: [entry, entry] }).success,
    ).toBe(false);
    expect(
      avatarManifestSchema.safeParse({
        version: 2,
        avatars: [{ ...entry, url: "http://example.com/a.png" }],
      }).success,
    ).toBe(false);
    expect(
      avatarManifestSchema.safeParse({
        version: 2,
        avatars: [{ ...entry, profile: { ...avatar.profile, ageMin: 50, ageMax: 20 } }],
      }).success,
    ).toBe(false);
  });
});
