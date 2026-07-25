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
import { registerDomainRoutes } from "../../src/modules/domain/routes.js";
import { createDomainService } from "../../src/modules/domain/service.js";
import type {
  Ticket,
  TravelResult,
  UserSnapshot,
} from "../../src/modules/domain/types.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  userId: string;
}>;

describe.runIf(runIntegrationTests)("authoritative user economy and travel", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let accessToken: string;
  let userId: string;
  const verificationTokens = new Map<string, string>();
  const email = `domain-${newEntityId()}@example.com`;
  const password = "Correct Horse Domain 1!";

  const authenticated = (
    options: {
      idempotencyKey?: string;
    } = {},
  ) => ({
    authorization: `Bearer ${accessToken}`,
    ...(options.idempotencyKey === undefined
      ? {}
      : { "idempotency-key": options.idempotencyKey }),
  });

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
    const domainService = createDomainService(dependencies.database);
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
    registerDomainRoutes(app, authService, domainService, {
      enableDebugRoutes: true,
    });

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
        device: {
          deviceId: "domain-test-device",
          platform: "ios",
        },
        email,
        password,
      },
      url: "/v1/auth/login",
    });
    const tokens = login.json<TokenResponse>();
    accessToken = tokens.accessToken;
    userId = tokens.userId;
  });

  afterAll(async () => {
    await app.close();
    await dependencies.database.sql`
      delete from app.jobs
      where user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.auth_security_events
      where user_id = ${userId}
    `;
    await dependencies.database.sql`
      delete from app.users
      where id = ${userId}
    `;
    await dependencies.close();
  });

  it("keeps assets correct under retries, unlocks, and concurrent travel", async () => {
    const initial = await app.inject({
      headers: authenticated(),
      method: "GET",
      url: "/v1/me",
    });
    expect(initial.statusCode).toBe(200);
    const initialSnapshot = initial.json<UserSnapshot>();
    expect(initialSnapshot.profile.currentRegionId).toBe("london");
    expect(initialSnapshot.profile.coins).toBe(0);
    expect(initialSnapshot.profile.unlockedRegionIds).toEqual(["london"]);

    const prematureStarter = await app.inject({
      headers: authenticated({ idempotencyKey: newEntityId() }),
      method: "POST",
      url: "/v1/progression/starter-ticket",
    });
    expect(prematureStarter.statusCode).toBe(409);
    expect(prematureStarter.json<{ code: string }>().code).toBe("ONBOARDING_REQUIRED");

    const profileCommand = newEntityId();
    const profileUpdate = await app.inject({
      headers: authenticated({ idempotencyKey: profileCommand }),
      method: "PATCH",
      payload: {
        displayName: "跨平台旅行者",
        expectedVersion: initialSnapshot.profile.version,
        hasCompletedOnboarding: true,
      },
      url: "/v1/me",
    });
    expect(profileUpdate.statusCode).toBe(200);
    expect(
      profileUpdate.json<{ displayName: string; version: number }>(),
    ).toMatchObject({
      displayName: "跨平台旅行者",
      version: initialSnapshot.profile.version + 1,
    });

    const staleProfileUpdate = await app.inject({
      headers: authenticated({ idempotencyKey: newEntityId() }),
      method: "PATCH",
      payload: {
        quizGloballyEnabled: false,
        expectedVersion: initialSnapshot.profile.version,
      },
      url: "/v1/me",
    });
    expect(staleProfileUpdate.statusCode).toBe(409);
    expect(staleProfileUpdate.json<{ code: string }>().code).toBe(
      "PROFILE_VERSION_CONFLICT",
    );

    const noTicket = await app.inject({
      headers: authenticated({ idempotencyKey: newEntityId() }),
      method: "POST",
      payload: { targetRegionId: "melbourne" },
      url: "/v1/travel",
    });
    expect(noTicket.statusCode).toBe(409);
    expect(noTicket.json<{ code: string }>().code).toBe("TICKET_REQUIRED");

    const starterCommand = newEntityId();
    const starterTicket = await app.inject({
      headers: authenticated({ idempotencyKey: starterCommand }),
      method: "POST",
      url: "/v1/progression/starter-ticket",
    });
    expect(starterTicket.statusCode).toBe(200);
    expect(starterTicket.json<Ticket>()).toMatchObject({
      source: "quest",
      type: "universal",
    });
    const starterRetry = await app.inject({
      headers: authenticated({ idempotencyKey: starterCommand }),
      method: "POST",
      url: "/v1/progression/starter-ticket",
    });
    expect(starterRetry.json<Ticket>()).toEqual(starterTicket.json<Ticket>());
    const duplicateStarter = await app.inject({
      headers: authenticated({ idempotencyKey: newEntityId() }),
      method: "POST",
      url: "/v1/progression/starter-ticket",
    });
    expect(duplicateStarter.statusCode).toBe(409);
    expect(duplicateStarter.json<{ code: string }>().code).toBe(
      "STARTER_TICKET_ALREADY_CLAIMED",
    );

    const grantCommand = newEntityId();
    const grant = await app.inject({
      headers: authenticated({ idempotencyKey: grantCommand }),
      method: "POST",
      payload: { amount: 1000 },
      url: "/v1/dev/economy/coins",
    });
    expect(grant.statusCode).toBe(200);
    expect(grant.json<{ coins: number }>().coins).toBe(1000);

    const grantRetry = await app.inject({
      headers: authenticated({ idempotencyKey: grantCommand }),
      method: "POST",
      payload: { amount: 1000 },
      url: "/v1/dev/economy/coins",
    });
    expect(grantRetry.json<{ coins: number }>().coins).toBe(1000);

    const grantConflict = await app.inject({
      headers: authenticated({ idempotencyKey: grantCommand }),
      method: "POST",
      payload: { amount: 999 },
      url: "/v1/dev/economy/coins",
    });
    expect(grantConflict.statusCode).toBe(409);
    expect(grantConflict.json<{ code: string }>().code).toBe(
      "IDEMPOTENCY_KEY_CONFLICT",
    );

    const purchase = await app.inject({
      headers: authenticated({ idempotencyKey: newEntityId() }),
      method: "POST",
      payload: { type: "universal" },
      url: "/v1/economy/tickets/purchase",
    });
    expect(purchase.statusCode).toBe(200);
    const purchased = purchase.json<{ coins: number; ticket: Ticket }>();
    expect(purchased.coins).toBe(500);

    const travelCommand = newEntityId();
    const firstTravel = await app.inject({
      headers: authenticated({ idempotencyKey: travelCommand }),
      method: "POST",
      payload: {
        targetRegionId: "melbourne",
        ticketId: purchased.ticket.id,
      },
      url: "/v1/travel",
    });
    expect(firstTravel.statusCode).toBe(200);
    const firstTravelResult = firstTravel.json<TravelResult>();
    expect(firstTravelResult.unlockedNow).toBe(true);
    expect(firstTravelResult.consumedTicketId).toBe(purchased.ticket.id);

    const travelRetry = await app.inject({
      headers: authenticated({ idempotencyKey: travelCommand }),
      method: "POST",
      payload: {
        targetRegionId: "melbourne",
        ticketId: purchased.ticket.id,
      },
      url: "/v1/travel",
    });
    expect(travelRetry.statusCode).toBe(200);
    expect(travelRetry.json<TravelResult>()).toEqual(firstTravelResult);

    const returnToLondon = await app.inject({
      headers: authenticated({ idempotencyKey: newEntityId() }),
      method: "POST",
      payload: { targetRegionId: "london" },
      url: "/v1/travel",
    });
    expect(returnToLondon.statusCode).toBe(200);
    expect(returnToLondon.json<TravelResult>().consumedTicketId).toBeNull();

    const ticketResponses = await Promise.all(
      [newEntityId(), newEntityId()].map((idempotencyKey) =>
        app.inject({
          headers: authenticated({ idempotencyKey }),
          method: "POST",
          payload: { type: "universal" },
          url: "/v1/dev/economy/tickets",
        }),
      ),
    );
    const tickets = ticketResponses.map((response) => response.json<Ticket>());

    const concurrentTravel = await Promise.all(
      tickets.map((ticket) =>
        app.inject({
          headers: authenticated({ idempotencyKey: newEntityId() }),
          method: "POST",
          payload: {
            targetRegionId: "newyork",
            ticketId: ticket.id,
          },
          url: "/v1/travel",
        }),
      ),
    );
    expect(concurrentTravel.map((response) => response.statusCode).sort()).toEqual([
      200, 409,
    ]);

    const finalSnapshotResponse = await app.inject({
      headers: authenticated(),
      method: "GET",
      url: "/v1/me",
    });
    const finalSnapshot = finalSnapshotResponse.json<UserSnapshot>();
    expect(finalSnapshot.profile.currentRegionId).toBe("newyork");
    expect(finalSnapshot.profile.unlockedRegionIds).toEqual([
      "london",
      "melbourne",
      "newyork",
    ]);
    expect(finalSnapshot.tickets).toHaveLength(2);

    const [ledger] = await dependencies.database.sql<
      { current_balance: number; ledger_sum: number }[]
    >`
      select
        p.coins as current_balance,
        coalesce(sum(l.delta), 0)::int as ledger_sum
      from app.user_profiles p
      left join app.coin_ledger l on l.user_id = p.user_id
      where p.user_id = ${userId}
      group by p.coins
    `;
    expect(ledger?.current_balance).toBe(500);
    expect(ledger?.ledger_sum).toBe(500);

    const storyCommand = newEntityId();
    const storyCompletion = await app.inject({
      headers: authenticated({ idempotencyKey: storyCommand }),
      method: "POST",
      url: "/v1/progression/stories/mainline_london/complete",
    });
    expect(storyCompletion.statusCode).toBe(200);
    expect(
      storyCompletion.json<{
        coins: number;
        rewardCoins: number;
        storyId: string;
      }>(),
    ).toEqual({
      coins: 600,
      rewardCoins: 100,
      storyId: "mainline_london",
    });
    const storyRetry = await app.inject({
      headers: authenticated({ idempotencyKey: storyCommand }),
      method: "POST",
      url: "/v1/progression/stories/mainline_london/complete",
    });
    expect(storyRetry.json<unknown>()).toEqual(storyCompletion.json<unknown>());
    const duplicateStory = await app.inject({
      headers: authenticated({ idempotencyKey: newEntityId() }),
      method: "POST",
      url: "/v1/progression/stories/mainline_london/complete",
    });
    expect(duplicateStory.statusCode).toBe(409);
    expect(duplicateStory.json<{ code: string }>().code).toBe(
      "STORY_ALREADY_COMPLETED",
    );
    const unknownStory = await app.inject({
      headers: authenticated({ idempotencyKey: newEntityId() }),
      method: "POST",
      url: "/v1/progression/stories/mainline_unknown/complete",
    });
    expect(unknownStory.statusCode).toBe(404);
    expect(unknownStory.json<{ code: string }>().code).toBe("STORY_NOT_FOUND");
  }, 30_000);
});
