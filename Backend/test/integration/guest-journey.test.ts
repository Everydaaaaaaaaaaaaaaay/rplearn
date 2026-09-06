import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { loadConfig } from "../../src/config/env.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { createGuestClaim } from "../../src/infrastructure/guest-claim.js";
import { createAuthService, type AuthService } from "../../src/modules/auth/service.js";
import { createGuestService } from "../../src/modules/auth/guest-service.js";
import { registerGuestRoutes } from "../../src/modules/auth/guest-routes.js";
import { authenticateRequest } from "../../src/modules/auth/http.js";
import { registerNpcRoutes } from "../../src/modules/npc/routes.js";
import { createNpcService } from "../../src/modules/npc/service.js";
import { newEntityId } from "../../src/shared/id.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "anonymous journey ownership",
  () => {
    let app: FastifyInstance;
    let runtime: RuntimeDependencies;
    let auth: AuthService;
    const ids: string[] = [];
    const npcID = newEntityId();
    const avatarID = newEntityId();
    const key = newEntityId().replaceAll("-", "") + newEntityId().replaceAll("-", "");
    const device = { deviceId: "guest-test", platform: "ios" as const };
    const headers = (token: string) => ({ authorization: `Bearer ${token}` });

    beforeAll(async () => {
      const config = loadConfig({ ...process.env, NODE_ENV: "test" });
      runtime = createRuntimeDependencies(config);
      await runMigrations(runtime.database);
      await runtime.start();
      auth = await createAuthService(config, runtime.database);
      app = await buildApp(config, { logger: false });
      registerGuestRoutes(
        app,
        auth,
        createGuestService(config, runtime.database, auth),
        createGuestClaim(runtime.database, config.authTokenHashPepper),
      );
      registerNpcRoutes(app, auth, createNpcService(runtime.database));
      app.get("/test/account", async (request) => authenticateRequest(request, auth));
      await runtime.database
        .sql`insert into app.npc_avatars (id, image_url, tags) values (${avatarID}, ${`https://example.com/${avatarID}.png`}, '["gender:female","age:adult"]')`;
    });

    afterAll(async () => {
      await app.close();
      {
        await runtime.database.sql`delete from app.public_npcs where id = ${npcID}`;
        for (const id of ids)
          await runtime.database.sql`delete from app.users where id = ${id}`;
        await runtime.database.sql`delete from app.npc_avatars where id = ${avatarID}`;
        await runtime.close();
      }
    });

    it("resumes one anonymous identity, registers permanently, and claims once without freeing seen portraits", async () => {
      const sessions = await Promise.all(
        [1, 2].map(() =>
          app.inject({
            method: "POST",
            url: "/v1/auth/guest",
            payload: { installationKey: key, device },
          }),
        ),
      );
      expect(sessions.map((s) => s.statusCode)).toEqual([200, 200]);
      const resumed = await app.inject({
        method: "POST",
        url: "/v1/auth/guest",
        payload: { installationKey: key, device },
      });
      const guest = resumed.json<{ userId: string; accessToken: string }>();
      ids.push(guest.userId);
      expect(sessions[1]?.json<{ userId: string }>().userId).toBe(guest.userId);
      expect((await auth.authenticate(guest.accessToken)).isGuest).toBe(true);
      expect(
        (
          await app.inject({
            url: "/test/account",
            headers: headers(guest.accessToken),
          })
        ).statusCode,
      ).toBe(403);
      const card = {
        name: "Yuki Test",
        age: 29,
        gender: "female",
        appearance: "short hair",
        hobbies: ["books"],
        nationality: "Japanese",
        occupation: "designer",
        personality: "curious",
        regionId: "london",
        languages: ["English"],
        personaVoice: {
          anchorLines: [],
          boundaries: [],
          conversationalHabits: [],
          flaws: [],
          values: [],
        },
      };
      const request = {
        method: "POST" as const,
        url: "/v1/npcs",
        headers: headers(guest.accessToken),
        payload: { id: npcID, card },
      };
      const first = await app.inject(request);
      expect(first.statusCode).toBe(200);
      const repeated = await app.inject(request);
      expect(repeated.json()).toEqual(first.json());
      const accountId = newEntityId();
      ids.push(accountId);
      await runtime.database.sql`insert into app.users (id) values (${accountId})`;
      const account = await auth.loginFederated(accountId, 0, device, {});
      const claim = {
        method: "POST" as const,
        url: "/v1/auth/guest/claim",
        headers: headers(account.accessToken),
        payload: { installationKey: key },
      };
      expect((await app.inject(claim)).json()).toEqual({ claimed: true });
      expect((await app.inject(claim)).json()).toEqual({ claimed: true });
      const relations = await runtime.database
        .sql<{ npc_id: string }[]>`select npc_id from app.user_npc_relationships where user_id = ${accountId}`;
      expect(relations.map((r) => r.npc_id)).toContain(npcID);
      expect((await app.inject(request)).statusCode).toBe(401);
      expect(
        (
          await app.inject({
            method: "POST",
            url: "/v1/auth/guest",
            payload: { installationKey: key, device },
          })
        ).statusCode,
      ).toBe(403);
      const otherId = newEntityId();
      ids.push(otherId);
      await runtime.database.sql`insert into app.users (id) values (${otherId})`;
      const other = await auth.loginFederated(otherId, 0, device, {});
      expect(
        (await app.inject({ ...claim, headers: headers(other.accessToken) }))
          .statusCode,
      ).toBe(409);
    });
  },
);
