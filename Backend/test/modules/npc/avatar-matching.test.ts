import { describe, expect, it } from "vitest";
import {
  avatarMetadataSchema,
  avatarManifestSchema,
} from "../../../src/modules/npc/avatar-catalog.js";
import { auditAvatarCoverage } from "../../../src/modules/npc/avatar-coverage.js";
import {
  avatarPreference,
  chooseAvatar,
  mentions,
  rankAvatars,
} from "../../../src/modules/npc/avatar-matching.js";
import { avatarMetadata, npcCard } from "../../helpers/npc-avatars.js";

const candidate = (id: string, cultures: string[], expressions: string[] = []) => ({
  id,
  familyId: id,
  metadata: { ...avatarMetadata, cultures, subjects: [], aesthetics: [], expressions },
});
describe("cultural avatar choice", () => {
  it("matches interests across languages without inferring tastes from appearance or nationality", () => {
    const preference = avatarPreference(npcCard);
    expect(preference.interests).toContain("badminton");
    expect(preference.interests).toContain("japan");
    expect(
      avatarPreference({
        ...npcCard,
        age: 85,
        gender: "male",
        nationality: "Japanese",
        appearance: "different",
      } as typeof npcCard),
    ).toEqual(preference);
    expect(avatarPreference({ ...npcCard, hobbies: ["jazz"] }).interests).toEqual([
      "jazz",
    ]);
    expect(
      avatarPreference({ ...npcCard, hobbies: ["バドミントン"] }).interests,
    ).toContain("badminton");
    expect(mentions("theatre", "tea")).toBe(false);
  });
  it("searches beyond 64 assets and prefers cultural overlap over a merely similar mood", () => {
    const candidates = Array.from({ length: 100 }, (_, i) =>
      candidate(`other-${String(i)}`, ["jazz"], ["quiet"]),
    );
    candidates.push(candidate("right", ["badminton", "japan"]));
    expect(chooseAvatar(candidates, avatarPreference(npcCard), "u:n")?.avatar.id).toBe(
      "right",
    );
  });
  it("does not mistake a shared mood for an unrelated cultural interest", () => {
    const preference = avatarPreference(npcCard);
    const jazz = candidate("jazz", ["jazz"], ["quiet"]);
    expect(chooseAvatar([jazz], preference, "u:n")).toBeUndefined();
    const abstract = {
      ...jazz,
      metadata: { ...jazz.metadata, cultures: ["abstract"], interestIndependent: true },
    };
    expect(chooseAvatar([abstract], preference, "u:n")?.avatar.id).toBe("jazz");
  });

  it("supports unlisted cultural entities and stable varied choices", () => {
    const preference = avatarPreference({
      hobbies: ["Hollow Knight"],
      personality: "",
    });
    const assets = Array.from({ length: 8 }, (_, i) =>
      candidate(String(i), ["Hollow Knight"]),
    );
    expect(rankAvatars(assets, preference)).toHaveLength(8);
    expect(chooseAvatar(assets, preference, "one")).toEqual(
      chooseAvatar([...assets].reverse(), preference, "one"),
    );
    expect(
      new Set(
        Array.from(
          { length: 30 },
          (_, i) => chooseAvatar(assets, preference, String(i))?.avatar.id,
        ),
      ).size,
    ).toBeGreaterThan(1);
    expect(
      chooseAvatar([candidate("no", ["cricket"])], preference, "one"),
    ).toBeUndefined();
  });
  it("rejects unreviewed provenance and generated artwork without generation records", () => {
    expect(
      avatarMetadataSchema.safeParse({
        ...avatarMetadata,
        source: { ...avatarMetadata.source, commercialUse: false },
      }).success,
    ).toBe(false);
    expect(
      avatarMetadataSchema.safeParse({
        ...avatarMetadata,
        source: { ...avatarMetadata.source, kind: "generated" },
      }).success,
    ).toBe(false);
  });
  it("reports family depletion, coverage gaps and unknown interests", () => {
    const asset = {
      ...candidate("00000000-0000-4000-8000-000000000001", ["badminton"]),
      sha256: "a".repeat(64),
      url: "https://example.com/a.png",
      enabled: true,
      reserved: false,
    };
    const variant = {
      ...asset,
      id: "00000000-0000-4000-8000-000000000002",
      sha256: "b".repeat(64),
      url: "https://example.com/b.png",
    };
    const manifest = avatarManifestSchema.parse({
      version: 2,
      avatars: [asset, variant],
    });
    const report = auditAvatarCoverage(manifest, [
      { id: "1", hobbies: ["badminton"], personality: "" },
      { id: "2", hobbies: ["badminton"], personality: "" },
      { id: "3", hobbies: ["unknown new subculture"], personality: "" },
    ]);
    expect(report.families).toBe(1);
    expect(report.depleted).toBe(1);
    expect(report.unmatched).toBe(1);
    expect(report.unrecognizedInterests).toContain("unknown new subculture");
    expect(report.replenishment.length).toBeGreaterThan(0);
    expect(
      avatarManifestSchema.safeParse({ version: 2, avatars: [asset, asset] }).success,
    ).toBe(false);
  });
});
