import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { integrationConfig as loadConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import type { AuthNotifier } from "../../src/modules/auth/notifier.js";
import { registerAuthRoutes } from "../../src/modules/auth/routes.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { createContentCursorCodec } from "../../src/modules/content/cursor.js";
import { registerContentRoutes } from "../../src/modules/content/routes.js";
import { createContentService } from "../../src/modules/content/service.js";
import type {
  ContentCommandResult,
  ContentPage,
} from "../../src/modules/content/types.js";
import { createSyncCursorCodec } from "../../src/modules/sync/cursor.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  userId: string;
}>;

describe.runIf(runIntegrationTests)("cross-platform user content", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let accessToken: string;
  let userId: string;
  const email = `content-${newEntityId()}@example.com`;
  const password = "Correct Horse Content 1!";
  const verificationTokens = new Map<string, string>();

  const headers = () => ({
    authorization: `Bearer ${accessToken}`,
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
    const syncCursor = createSyncCursorCodec(config.authTokenHashPepper);
    const contentService = createContentService(
      dependencies.database,
      createContentCursorCodec(config.authTokenHashPepper),
      syncCursor,
    );
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
    registerContentRoutes(app, authService, contentService);

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
          deviceId: "content-test-device",
          platform: "ios",
        },
        email,
        password,
      },
      url: "/v1/auth/login",
    });
    const token = login.json<TokenResponse>();
    accessToken = token.accessToken;
    userId = token.userId;
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

  it("validates typed records, enforces hierarchy, versions, idempotency, and pages", async () => {
    const characterId = newEntityId();
    const conversationId = newEntityId();
    const messageId = newEntityId();
    const now = new Date().toISOString();
    const commands = [
      {
        commandId: newEntityId(),
        expectedVersion: 0,
        operation: "upsert",
        parentId: null,
        payload: {
          card: {
            age: 28,
            appearance: "Brown hair",
            avatarAssetName: null,
            background: "Local guide",
            gender: "female",
            hobbies: ["books"],
            name: "Alice",
            nationality: "British",
            occupation: "Guide",
            personality: "Warm",
            activityProfile: {
              focusDurationMinutes: 8,
              rhythm: "earlyBird",
              timeZoneIdentifier: "Europe/London",
            },
            regionId: "london",
            speechStyle: "Friendly",
          },
          difficulty: "junior3",
          growth: { schemaVersion: 2, revision: 1, isPaused: true, arcs: [] },
          isFriend: true,
          isMainCharacter: true,
          metAt: now,
          relationship: {
            activityCountToday: 1,
            activityDayStart: now,
            affinity: 12,
            bondFloor: 5.1,
            care: 0.12,
            expectedSocialQuality: 0.4,
            familiarity: 0.1,
            interactionCount: 1,
            interactionStability: 0.5,
            substantiveIntervalSampleCount: 3,
            lastEvaluatedOrderIndex: 0,
            lastInteractionAt: now,
            lastSubstantiveInteractionAt: now,
            meaningfulInteractionCount: 0,
            positiveGainToday: 0.2,
            rapport: 0.12,
            recentEvents: [],
            repairGainToday: 0,
            respect: 0.55,
            revision: 1,
            schemaVersion: 3,
            typicalContactIntervalDays: 14,
            trust: 0.14,
            unresolvedStrain: 0,
          },
          schemaVersion: 1,
        },
        resourceId: characterId,
        resourceType: "character",
      },
      {
        commandId: newEntityId(),
        expectedVersion: 0,
        operation: "upsert",
        parentId: characterId,
        payload: {
          createdAt: now,
          isArchived: false,
          isEncounterSession: false,
          lastMessageAt: now,
          lastSummarizedMessageIndex: 0,
          quizOptOut: false,
          schemaVersion: 1,
          turnCount: 0,
          turnsSinceQuiz: 0,
        },
        resourceId: conversationId,
        resourceType: "conversation",
      },
      {
        commandId: newEntityId(),
        expectedVersion: 0,
        operation: "upsert",
        parentId: conversationId,
        payload: {
          audioAssetId: null,
          audioDuration: null,
          coachReviewJson: null,
          createdAt: now,
          isInterrupted: false,
          keywordRangesJson: null,
          kind: "text",
          orderIndex: 0,
          quizChosenIndex: null,
          quizJson: null,
          role: "user",
          schemaVersion: 1,
          speechReviewJson: null,
          text: "Hello",
          tokenEstimate: 1,
          translationZh: null,
        },
        resourceId: messageId,
        resourceType: "message",
      },
    ] as const;

    const upload = await app.inject({
      headers: headers(),
      method: "POST",
      payload: { commands },
      url: "/v1/content/commands",
    });
    expect(upload.statusCode).toBe(200);
    const uploadBody = upload.json<{ results: readonly ContentCommandResult[] }>();
    expect(uploadBody.results.map((result) => result.status)).toEqual([
      "applied",
      "applied",
      "applied",
    ]);

    const replay = await app.inject({
      headers: headers(),
      method: "POST",
      payload: { commands },
      url: "/v1/content/commands",
    });
    expect(replay.json<unknown>()).toEqual(uploadBody);

    const conflict = await app.inject({
      headers: headers(),
      method: "POST",
      payload: {
        commands: [
          {
            ...commands[2],
            commandId: newEntityId(),
            payload: { ...commands[2].payload, text: "Conflicting edit" },
          },
        ],
      },
      url: "/v1/content/commands",
    });
    expect(
      conflict.json<{ results: readonly ContentCommandResult[] }>().results[0],
    ).toMatchObject({
      error: { code: "CONTENT_VERSION_CONFLICT" },
      status: "rejected",
    });

    const missingParent = await app.inject({
      headers: headers(),
      method: "POST",
      payload: {
        commands: [
          {
            ...commands[2],
            commandId: newEntityId(),
            parentId: newEntityId(),
            resourceId: newEntityId(),
          },
        ],
      },
      url: "/v1/content/commands",
    });
    expect(
      missingParent.json<{ results: readonly ContentCommandResult[] }>().results[0],
    ).toMatchObject({
      error: { code: "CONTENT_PARENT_NOT_FOUND" },
      status: "rejected",
    });

    const unavailableMedia = await app.inject({
      headers: headers(),
      method: "POST",
      payload: {
        commands: [
          {
            ...commands[2],
            commandId: newEntityId(),
            parentId: conversationId,
            payload: {
              ...commands[2].payload,
              audioAssetId: newEntityId(),
              audioDuration: 1.5,
              kind: "voice",
            },
            resourceId: newEntityId(),
          },
        ],
      },
      url: "/v1/content/commands",
    });
    expect(
      unavailableMedia.json<{ results: readonly ContentCommandResult[] }>().results[0],
    ).toMatchObject({
      error: { code: "MEDIA_ASSET_NOT_READY" },
      status: "rejected",
    });

    const firstPageResponse = await app.inject({
      headers: headers(),
      method: "GET",
      url: "/v1/content/records?limit=2",
    });
    expect(firstPageResponse.statusCode).toBe(200);
    const firstPage = firstPageResponse.json<ContentPage>();
    expect(firstPage.records).toHaveLength(2);
    expect(firstPage.records.find((record) => record.resourceId === characterId)?.payload).toMatchObject({
      card: {
        activityProfile: {
          focusDurationMinutes: 8,
          rhythm: "earlyBird",
          timeZoneIdentifier: "Europe/London",
        },
      },
      growth: { schemaVersion: 2, isPaused: true },
    });
    expect(firstPage.hasMore).toBe(true);
    expect(firstPage.nextCursor).toBeTypeOf("string");
    expect(firstPage.syncCursor).toBeTypeOf("string");
    const nextCursor = firstPage.nextCursor;
    if (nextCursor === null) {
      throw new Error("The first content page did not include a cursor");
    }

    const secondPage = (
      await app.inject({
        headers: headers(),
        method: "GET",
        url: `/v1/content/records?limit=2&cursor=${encodeURIComponent(nextCursor)}`,
      })
    ).json<ContentPage>();
    expect(secondPage.records).toHaveLength(1);
    expect(secondPage.records[0]?.resourceId).toBe(messageId);
    expect(secondPage.hasMore).toBe(false);

    const tampered = await app.inject({
      headers: headers(),
      method: "GET",
      url: `/v1/content/records?cursor=${encodeURIComponent(`${nextCursor.slice(0, -1)}x`)}`,
    });
    expect(tampered.statusCode).toBe(400);
    expect(tampered.json<{ code: string }>().code).toBe("INVALID_CONTENT_CURSOR");

    const deleteParent = await app.inject({
      headers: headers(),
      method: "POST",
      payload: {
        commands: [
          {
            commandId: newEntityId(),
            expectedVersion: 1,
            operation: "delete",
            resourceId: characterId,
            resourceType: "character",
          },
        ],
      },
      url: "/v1/content/commands",
    });
    expect(
      deleteParent.json<{ results: readonly ContentCommandResult[] }>().results[0],
    ).toMatchObject({
      error: { code: "CONTENT_HAS_DEPENDENTS" },
      status: "rejected",
    });

    const deleteMessage = await app.inject({
      headers: headers(),
      method: "POST",
      payload: {
        commands: [
          {
            commandId: newEntityId(),
            expectedVersion: 1,
            operation: "delete",
            resourceId: messageId,
            resourceType: "message",
          },
        ],
      },
      url: "/v1/content/commands",
    });
    expect(
      deleteMessage.json<{ results: readonly ContentCommandResult[] }>().results[0],
    ).toMatchObject({
      record: {
        deletedAt: expect.any(String) as string,
        version: 2,
      },
      status: "applied",
    });
  }, 30_000);
});
