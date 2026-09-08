import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { runMigrations } from "../../src/db/migrate.js";
import { integrationConfig as loadConfig } from "../helpers/integration.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { createNpcService, type NpcService } from "../../src/modules/npc/service.js";
import type {
  NpcDiversityProfile,
  PublicNpcCard,
} from "../../src/modules/npc/types.js";
import { newEntityId } from "../../src/shared/id.js";

function required<T>(value: T | null | undefined): T {
  if (value === undefined || value === null) throw new Error("Missing test fixture");
  return value;
}

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "NPC persona diversity admission",
  () => {
    let runtime: RuntimeDependencies;
    let service: NpcService;
    const userId = newEntityId();
    const regionId = `diversity-${userId.slice(0, 8)}`;
    const npcIds = Array.from({ length: 6 }, () => newEntityId());
    const avatarIds = Array.from({ length: 4 }, () => newEntityId());

    const profile: NpcDiversityProfile = {
      version: 1,
      occupationDomain: "service-retail",
      socialRole: "creator",
      interactionStyle: "gentle",
      interestDomains: ["nature", "crafts-making"],
      traits: ["empathetic", "careful"],
      backgroundMotif: "mastery",
      energy: "medium",
      warmth: "warm",
      structure: "balanced",
    };
    const context = {
      regionId,
      activityId: "persona-admission-test",
      category: "social" as const,
      language: "English",
    };
    const card = (name: string, background: string): PublicNpcCard => ({
      age: 31,
      appearance: "Provisional portrait",
      background,
      birthday: "04-19",
      gender: "female",
      hobbies: ["园艺", "修复旧花盆", "骑行"],
      hometown: "Brighton",
      languages: ["English"],
      name,
      nationality: "British",
      occupation: "weekend plant seller",
      personaVoice: {
        anchorLines: ["Give me a second, love."],
        boundaries: ["does not mock sincere questions"],
        conversationalHabits: ["notices small details", "uses gentle humour"],
        flaws: ["sometimes forgetful"],
        values: ["kindness", "craft"],
      },
      personality: "warm, observant and a little forgetful",
      regionId,
      signature: "Plants reward patience.",
      speechStyle: "soft, quick and gently humorous",
    });

    beforeAll(async () => {
      const config = loadConfig({ ...process.env, NODE_ENV: "test" });
      runtime = createRuntimeDependencies(config);
      await runMigrations(runtime.database);
      await runtime.start();
      service = createNpcService(runtime.database, () => 0);
      await runtime.database.sql`insert into app.users (id) values (${userId})`;
      for (const avatarId of avatarIds)
        await runtime.database.sql`
          insert into app.npc_avatars (id, image_url, tags, profile)
          values (
            ${avatarId}, ${`https://example.com/${avatarId}.png`}, '[]'::jsonb,
            ${JSON.stringify({ ageMin: 25, ageMax: 44, gender: "female", appearance: "Reviewed portrait", styleVersion: "test", sha256: "a".repeat(64) })}::jsonb
          )
        `;
    });

    afterAll(async () => {
      await runtime.database
        .sql`delete from app.npc_pending_avatars where npc_id in ${runtime.database.sql(npcIds)}`;
      await runtime.database
        .sql`delete from app.public_npcs where id in ${runtime.database.sql(npcIds)}`;
      await runtime.database.sql`delete from app.users where id = ${userId}`;
      await runtime.database
        .sql`delete from app.npc_avatars where id in ${runtime.database.sql(avatarIds)}`;
      await runtime.close();
    });

    it("reviews before allocation and returns explainable regeneration guidance", async () => {
      const original = card(
        "Poppy Hale",
        "Runs a flower stall while mastering rare orchids.",
      );
      expect(
        await service.reviewDiversity(userId, {
          card: original,
          diversityProfile: profile,
          encounterContext: context,
        }),
      ).toMatchObject({ decision: "accept", similarityScore: 0 });
      await service.register(userId, {
        id: required(npcIds[0]),
        card: original,
        diversityProfile: profile,
        encounterContext: context,
      });
      const review = await service.reviewDiversity(userId, {
        card: card(
          "Mara Bell",
          "Keeps a market plant booth and practices difficult grafting techniques.",
        ),
        diversityProfile: profile,
        encounterContext: context,
      });
      expect(review.decision).toBe("revise");
      expect(review.dimensions).toContain("occupation-domain");
      expect(review.guidance.length).toBeGreaterThanOrEqual(2);
    });

    it("rejects duplicates before an avatar event or relationship can be written", async () => {
      const duplicateId = required(npcIds[1]);
      await expect(
        service.register(userId, {
          id: duplicateId,
          card: card(
            "Renamed Clone",
            "Runs a flower stall while mastering rare orchids.",
          ),
          diversityProfile: profile,
          encounterContext: context,
        }),
      ).rejects.toMatchObject({ code: "NPC_PERSONA_TOO_SIMILAR" });
      const events = await runtime.database.sql`
        select 1 from app.npc_avatar_match_events where npc_id = ${duplicateId}
      `;
      const relationships = await runtime.database.sql`
        select 1 from app.user_npc_relationships where npc_id = ${duplicateId}
      `;
      expect(events).toHaveLength(0);
      expect(relationships).toHaveLength(0);
    });

    it("serializes concurrent semantic admission so only one equivalent role wins", async () => {
      const racingProfile: NpcDiversityProfile = {
        ...profile,
        occupationDomain: "skilled-trades",
        socialRole: "problem-solver",
        interactionStyle: "practical",
        interestDomains: ["technology", "sports"],
        traits: ["pragmatic", "candid"],
        backgroundMotif: "fresh-start",
        warmth: "balanced",
        structure: "structured",
      };
      const results = await Promise.allSettled(
        [2, 3].map((index) =>
          service.register(userId, {
            id: required(npcIds[index]),
            card: {
              ...card(
                index === 2 ? "Dev Singh" : "Owen Price",
                index === 2
                  ? "Reopened a bicycle repair shop after changing careers."
                  : "Started a cycle workshop after leaving an office career.",
              ),
              occupation: index === 2 ? "bicycle mechanic" : "cycle repairer",
              personality: "direct, energetic and practical",
              speechStyle: "short, concrete technical answers",
            },
            diversityProfile: racingProfile,
            encounterContext: context,
          }),
        ),
      );
      expect(results.filter((result) => result.status === "fulfilled")).toHaveLength(1);
      const rejected = results.find((result) => result.status === "rejected");
      expect(rejected).toMatchObject({
        reason: { code: "NPC_PERSONA_TOO_SIMILAR" },
      });
    });

    it("treats an avatar-waiting identity as occupied persona supply", async () => {
      const pendingId = required(npcIds[4]);
      const rejectedId = required(npcIds[5]);
      const pendingProfile: NpcDiversityProfile = {
        ...profile,
        occupationDomain: "education",
        socialRole: "mentor",
        interactionStyle: "analytical",
        interestDomains: ["books-learning", "history-culture"],
        traits: ["disciplined", "curious"],
        backgroundMotif: "service",
        warmth: "balanced",
        structure: "structured",
      };
      const pendingCard = {
        ...card("Anika Shah", "Runs free evening history lessons for new arrivals."),
        occupation: "adult education tutor",
        hobbies: ["研究地方史", "整理口述档案"],
        personality: "precise, patient and quietly curious",
        speechStyle: "careful analytical questions",
      };
      await expect(
        service.register(userId, {
          id: pendingId,
          card: pendingCard,
          diversityProfile: pendingProfile,
          requiredAvatarTags: ["pose:not-yet-imported"],
          encounterContext: context,
        }),
      ).rejects.toMatchObject({ code: "NPC_AVATAR_COVERAGE_GAP" });
      await expect(
        service.register(userId, {
          id: rejectedId,
          card: { ...pendingCard, name: "A New Name" },
          diversityProfile: pendingProfile,
          requiredAvatarTags: ["pose:not-yet-imported"],
          encounterContext: context,
        }),
      ).rejects.toMatchObject({ code: "NPC_PERSONA_TOO_SIMILAR" });
      const pending = await runtime.database.sql`
        select npc_id from app.npc_pending_avatars where npc_id in ${runtime.database.sql([pendingId, rejectedId])}
      `;
      expect(pending).toHaveLength(1);
    });
  },
);
