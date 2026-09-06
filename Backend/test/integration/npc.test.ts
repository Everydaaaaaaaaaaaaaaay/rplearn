import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { loadConfig } from "../../src/config/env.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import type { AuthNotifier } from "../../src/modules/auth/notifier.js";
import { registerAuthRoutes } from "../../src/modules/auth/routes.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { registerNpcRoutes } from "../../src/modules/npc/routes.js";
import { createNpcService } from "../../src/modules/npc/service.js";
import type { PublicNpc } from "../../src/modules/npc/types.js";
import { importAvatarManifest } from "../../src/modules/npc/avatar-import.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{ accessToken: string; userId: string }>;

describe.runIf(runIntegrationTests)("public NPC registry", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let accessToken: string;
  let userId: string;
  const firstNpcId = newEntityId();
  const secondNpcId = newEntityId();
  const pendingIds = [newEntityId(), newEntityId(), newEntityId()] as const;
  const pendingAssetIds = [newEntityId(), newEntityId()] as const;
  const avatarId = newEntityId();
  const supplementId = newEntityId();
  const concurrentIds = [secondNpcId, newEntityId()] as const;
  const email = `npc-${newEntityId()}@example.com`;
  const password = "Correct Horse NPC 1!";
  const verificationTokens = new Map<string, string>();

  const headers = () => ({ authorization: `Bearer ${accessToken}` });
  const card = {
    age: 29,
    appearance: "Short dark hair and a bright green jacket",
    background: "A community radio producer who collects neighborhood stories.",
    birthday: "04-18",
    gender: "female",
    hobbies: ["逛周末市场", "录制环境声音"],
    hometown: "Bristol",
    languages: ["English"],
    name: "Nora Hale",
    nationality: "British",
    occupation: "radio producer",
    personaVoice: {
      anchorLines: ["Give me the short version."],
      boundaries: ["does not pressure people"],
      conversationalHabits: ["asks concrete follow-up questions"],
      flaws: ["sometimes interrupts when excited"],
      values: ["curiosity", "fairness"],
    },
    personality: "Curious, candid, warm, and occasionally impatient",
    regionId: "london",
    signature: "Every street has a story if you slow down.",
    speechStyle: "Conversational British English with concise questions",
  } as const;

  const asset = (id: string) => ({
    id,
    url:
      id === avatarId
        ? "https://cdn.example.com/npc/nora.webp"
        : `https://cdn.example.com/npc/${id}.webp`,
    tags: ["theme:jade"],
    enabled: true,
    profile: {
      ageMin: 25,
      ageMax: 44,
      gender: "female" as const,
      appearance: "Reviewed short curls and jade scarf",
      styleVersion: "test",
      sha256: "a".repeat(64),
    },
  });

  beforeAll(async () => {
    const config = loadConfig({ ...process.env, NODE_ENV: "test" });
    dependencies = createRuntimeDependencies(config);
    await runMigrations(dependencies.database);
    await dependencies.start();
    const notifier: AuthNotifier = {
      sendEmailVerification: (destination, token) => {
        verificationTokens.set(destination, token);
        return Promise.resolve();
      },
      sendPasswordReset: () => Promise.resolve(),
    };
    const authService = await createAuthService(config, dependencies.database);
    const jobWorker = createTestJobWorker(config, dependencies.database, notifier);
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
    registerNpcRoutes(app, authService, createNpcService(dependencies.database));

    await app.inject({
      method: "POST",
      payload: { email, password },
      url: "/v1/auth/register",
    });
    expect(await jobWorker.runOnce()).toBe("succeeded");
    await app.inject({
      method: "POST",
      payload: { token: verificationTokens.get(email) },
      url: "/v1/auth/email/verify",
    });
    const login = await app.inject({
      method: "POST",
      payload: {
        device: { deviceId: "npc-test-device", platform: "ios" },
        email,
        password,
      },
      url: "/v1/auth/login",
    });
    const token = login.json<TokenResponse>();
    accessToken = token.accessToken;
    userId = token.userId;
    await importAvatarManifest(dependencies.database, {
      version: 2,
      avatars: [asset(avatarId)],
    });
  });

  afterAll(async () => {
    // Setup may fail before assignment.
    // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
    await app?.close();
    if (!userId) {
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
      await dependencies?.close();
      return;
    }
    await dependencies.database
      .sql`delete from app.public_npcs where id in ${dependencies.database.sql(pendingIds)}`;
    await dependencies.database.sql`
      delete from app.public_npcs where id in (${firstNpcId}, ${secondNpcId}, ${concurrentIds[0]}, ${concurrentIds[1]})
    `;
    await dependencies.database
      .sql`delete from app.npc_avatar_match_events where user_id = ${userId}`;
    await dependencies.database
      .sql`delete from app.npc_avatars where id in (${avatarId}, ${supplementId})`;
    await dependencies.database
      .sql`delete from app.npc_avatars where id in ${dependencies.database.sql(pendingAssetIds)}`;
    await dependencies.database.sql`delete from app.jobs where user_id = ${userId}`;
    await dependencies.database.sql`
      delete from app.auth_security_events where user_id = ${userId}
    `;
    await dependencies.database.sql`delete from app.users where id = ${userId}`;
    await dependencies.close();
  });

  it("allocates a unique checked traveler ID and permanently claims one avatar", async () => {
    const first = await app.inject({
      headers: headers(),
      method: "POST",
      payload: { card, id: firstNpcId },
      url: "/v1/npcs",
    });
    expect(first.statusCode).toBe(200);
    const registered = first.json<PublicNpc>();
    expect(registered.id).toBe(firstNpcId);
    expect(registered.travelerId).toMatch(/^[0-9]{11}$/);
    expect(registered.avatar).toEqual({
      id: avatarId,
      url: "https://cdn.example.com/npc/nora.webp",
    });

    expect(registered.card.appearance).toBe(asset(avatarId).profile.appearance);
    const canonical = await app.inject({
      headers: headers(),
      method: "POST",
      payload: { card: registered.card, id: firstNpcId },
      url: "/v1/npcs",
    });
    expect(canonical.statusCode).toBe(200);
    expect(canonical.json()).toEqual(registered);

    const replay = await app.inject({
      headers: headers(),
      method: "POST",
      payload: { card, id: firstNpcId },
      url: "/v1/npcs",
    });
    expect(replay.json<PublicNpc>()).toEqual(registered);

    const second = await app.inject({
      headers: headers(),
      method: "POST",
      payload: { card, id: secondNpcId },
      url: "/v1/npcs",
    });
    expect(second.statusCode).toBe(409);
    expect(second.json<{ code: string }>().code).toBe("NPC_AVATAR_COVERAGE_GAP");

    const publicLookup = await app.inject({
      method: "GET",
      url: `/v1/npcs/by-traveler-id/${registered.travelerId}`,
    });
    expect(publicLookup.statusCode).toBe(200);
    expect(publicLookup.json<PublicNpc>()).toEqual(registered);
  });

  it("keeps shared identity immutable and stores private relationship status separately", async () => {
    const conflict = await app.inject({
      headers: headers(),
      method: "POST",
      payload: { card: { ...card, occupation: "different" }, id: firstNpcId },
      url: "/v1/npcs",
    });
    expect(conflict.statusCode).toBe(409);
    expect(conflict.json<{ code: string }>().code).toBe("NPC_IDENTITY_CONFLICT");

    const linked = await app.inject({
      headers: headers(),
      method: "PUT",
      payload: { localCharacterId: firstNpcId, status: "friend" },
      url: `/v1/npcs/${firstNpcId}/relationship`,
    });
    expect(linked.statusCode).toBe(204);
    const [relationship] = await dependencies.database.sql<{ status: string }[]>`
      select status::text
      from app.user_npc_relationships
      where user_id = ${userId} and npc_id = ${firstNpcId}
    `;
    expect(relationship?.status).toBe("friend");
  });
  it("rolls back an import that tries to change a bound visual identity", async () => {
    await expect(
      importAvatarManifest(dependencies.database, {
        version: 2,
        avatars: [
          asset(supplementId),
          { ...asset(avatarId), url: "https://cdn.example.com/changed.png" },
        ],
      }),
    ).rejects.toThrow("Bound avatar is immutable");
    const rows = await dependencies.database
      .sql`select id from app.npc_avatars where id=${supplementId}`;
    expect(rows).toHaveLength(0);
  });

  it("persists a gap and safely retries after supplementation without concurrent reuse", async () => {
    const [gap] = await dependencies.database.sql<
      { reason: string }[]
    >`select reason from app.npc_avatar_match_events where user_id=${userId} and npc_id=${secondNpcId}`;
    expect(gap?.reason).toBe("user_pool_exhausted");
    await importAvatarManifest(dependencies.database, {
      version: 2,
      avatars: [asset(supplementId)],
    });
    const attempts = await Promise.all(
      concurrentIds.map((id) =>
        app.inject({
          headers: headers(),
          method: "POST",
          payload: { card, id },
          url: "/v1/npcs",
        }),
      ),
    );
    expect(attempts.map((r) => r.statusCode).sort()).toEqual([200, 409]);
    const successfulResponse = attempts.find((r) => r.statusCode === 200);
    if (!successfulResponse)
      throw Error("Expected one successful concurrent registration");
    const success = successfulResponse.json<PublicNpc>();
    expect(success.avatar?.id).toBe(supplementId);
    const [event] = await dependencies.database.sql<
      { reason: string }[]
    >`select reason from app.npc_avatar_match_events where user_id=${userId} and npc_id=${success.id}`;
    expect(event?.reason).toBe("matched");
    const replay = await app.inject({
      headers: headers(),
      method: "POST",
      payload: { card, id: success.id },
      url: "/v1/npcs",
    });
    expect(replay.statusCode).toBe(200);
    expect(replay.json()).toEqual(success);
  });
  it("durably queues hard constraints, wakes on import, and binds once across worker/client retries", async () => {
    // Finish the preceding scenario's unmatched fixture so it cannot consume this scenario's artwork.
    await dependencies.database
      .sql`delete from app.npc_pending_avatars where npc_id in (${concurrentIds[0]}, ${concurrentIds[1]})`;
    const requiredAvatarTags = ["pose:pending-test"];
    for (const id of pendingIds) {
      const result = await app.inject({
        headers: headers(),
        method: "POST",
        url: "/v1/npcs",
        payload: { id, card, requiredAvatarTags },
      });
      expect(result.statusCode).toBe(409);
    }
    const saved = await dependencies.database.sql<
      { input: unknown; card_hash: string }[]
    >`
      select input, card_hash from app.npc_pending_avatars where npc_id = ${pendingIds[0]}
    `;
    expect(saved[0]?.input).toEqual({ id: pendingIds[0], card, requiredAvatarTags });
    const otherOwner = newEntityId();
    await dependencies.database.sql`insert into app.users (id) values (${otherOwner})`;
    try {
      await expect(
        createNpcService(dependencies.database).register(otherOwner, {
          id: pendingIds[0],
          card,
          requiredAvatarTags,
        }),
      ).rejects.toMatchObject({ code: "NPC_IDENTITY_CONFLICT" });
    } finally {
      await dependencies.database.sql`delete from app.users where id = ${otherOwner}`;
    }
    const conflict = await app.inject({
      headers: headers(),
      method: "POST",
      url: "/v1/npcs",
      payload: { id: pendingIds[0], card: { ...card, age: 30 }, requiredAvatarTags },
    });
    expect(conflict.json<{ code: string }>().code).toBe("NPC_IDENTITY_CONFLICT");
    // A restarted service has no in-memory queue; it must read the original PostgreSQL request.
    const restarted = createNpcService(dependencies.database);
    await importAvatarManifest(dependencies.database, {
      version: 2,
      avatars: [{ ...asset(pendingAssetIds[0]), tags: requiredAvatarTags }],
    });
    await Promise.all([
      restarted.retryPendingAvatars(),
      createNpcService(dependencies.database).retryPendingAvatars(),
    ]);
    const bound = await dependencies.database.sql<
      { id: string; traveler_id: string; avatar_id: string }[]
    >`
      select id::text, traveler_id, avatar_id::text from app.public_npcs where id in ${dependencies.database.sql(pendingIds)}
    `;
    expect(bound).toHaveLength(1);
    expect(bound[0]?.avatar_id).toBe(pendingAssetIds[0]);
    const boundNpc = bound[0];
    if (!boundNpc) throw Error("Expected a bound NPC");
    const lookup = await app.inject({
      method: "GET",
      url: `/v1/npcs/by-traveler-id/${boundNpc.traveler_id}`,
    });
    const canonical = lookup.json<PublicNpc>();
    expect(canonical.card).toEqual({
      ...card,
      appearance: asset(pendingAssetIds[0]).profile.appearance,
    });
    for (const retryCard of [card, canonical.card]) {
      const retry = await app.inject({
        headers: headers(),
        method: "POST",
        url: "/v1/npcs",
        payload: { id: boundNpc.id, card: retryCard, requiredAvatarTags },
      });
      expect(retry.statusCode).toBe(200);
      expect(retry.json()).toEqual(canonical);
    }
    const remaining = await dependencies.database.sql<{ npc_id: string }[]>`
      select npc_id::text from app.npc_pending_avatars where npc_id in ${dependencies.database.sql(pendingIds)}
    `;
    expect(remaining).toHaveLength(2);
    await app.inject({
      headers: headers(),
      method: "PUT",
      url: `/v1/npcs/${boundNpc.id}/relationship`,
      payload: { localCharacterId: boundNpc.id, status: "friend" },
    });
    await importAvatarManifest(dependencies.database, {
      version: 2,
      avatars: [{ ...asset(pendingAssetIds[1]), tags: requiredAvatarTags }],
    });
    const contender = remaining[0]?.npc_id;
    if (!contender) throw Error("Expected a remaining request");
    await Promise.all([
      restarted.retryPendingAvatars(),
      app.inject({
        headers: headers(),
        method: "POST",
        url: "/v1/npcs",
        payload: { id: contender, card, requiredAvatarTags },
      }),
    ]);
    const allBound = await dependencies.database.sql<{ avatar_id: string }[]>`
      select avatar_id::text from app.public_npcs where id in ${dependencies.database.sql(pendingIds)}
    `;
    expect(allBound).toHaveLength(2);
    expect(new Set(allBound.map((row) => row.avatar_id)).size).toBe(2);
    const [friend] = await dependencies.database.sql<{ status: string }[]>`
      select status from app.user_npc_relationships where user_id = ${userId} and npc_id = ${boundNpc.id}
    `;
    expect(friend?.status).toBe("friend");
    const immutable = await restarted.find(boundNpc.traveler_id);
    expect(immutable).toEqual(canonical);
    const [unmatched] = await dependencies.database.sql<{ count: number }[]>`
      select count(*)::int as count from app.npc_pending_avatars where npc_id in ${dependencies.database.sql(pendingIds)}
    `;
    expect(unmatched?.count).toBe(1);
    expect(await restarted.retryPendingAvatars()).toEqual({ attempted: 0, matched: 0 });
    // Suspended/deleting accounts must not acquire more public identities from the worker.
    await dependencies.database
      .sql`update app.users set status = 'locked' where id = ${userId}`;
    try {
      await dependencies.database
        .sql`update app.npc_pending_avatars set next_attempt_at = now() where user_id = ${userId}`;
      expect(await restarted.retryPendingAvatars()).toEqual({
        attempted: 0,
        matched: 0,
      });
    } finally {
      await dependencies.database
        .sql`update app.users set status = 'active' where id = ${userId}`;
    }
    expect(await restarted.retryPendingAvatars()).toEqual({ attempted: 1, matched: 0 });
  });
});
