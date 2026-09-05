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
import { newEntityId } from "../../src/shared/id.js";
import { avatarMetadata } from "../helpers/npc-avatars.js";
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
  const avatarId = newEntityId();
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
    hobbies: ["羽毛球", "录制环境声音"],
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

  beforeAll(async () => {
    const config = loadConfig({ NODE_ENV: "test" });
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
    await dependencies.database.sql`
      insert into app.npc_avatars (id, family_id, image_url, metadata)
      values (
        ${avatarId},
        ${avatarId},
        'https://cdn.example.com/npc/nora.webp',
        ${JSON.stringify(avatarMetadata)}::jsonb
      )
    `;
  });

  afterAll(async () => {
    await app.close();
    await dependencies.database
      .sql`delete from app.user_npc_avatars where user_id = ${userId}`;
    await dependencies.database.sql`
      delete from app.public_npcs where id in (${firstNpcId}, ${secondNpcId})
    `;
    await dependencies.database.sql`delete from app.npc_avatars where id = ${avatarId}`;
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
      attribution: "Test artist",
      sourceUrl: "https://example.com/test-art",
    });

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
      payload: { card: { ...card, name: "Mara Hale" }, id: secondNpcId },
      url: "/v1/npcs",
    });
    expect(second.statusCode).toBe(503);
    expect(second.json<{ code: string }>().code).toBe("NPC_AVATAR_UNAVAILABLE");

    const publicLookup = await app.inject({
      headers: headers(),
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
});
