import { describe, expect, it, vi } from "vitest";
import { buildApp } from "../../../src/app.js";
import { loadConfig } from "../../../src/config/env.js";
import type { AuthService } from "../../../src/modules/auth/service.js";
import { registerContentRoutes } from "../../../src/modules/content/routes.js";
import type { ContentService } from "../../../src/modules/content/service.js";

const userId = "019c0123-4567-789a-8bcd-ef0123456789";

function authService(): AuthService {
  return {
    authenticate: (token) =>
      token === "valid-access-token"
        ? Promise.resolve({
            sessionId: "019c0123-4567-789a-8bcd-ef0123456788",
            tokenVersion: 0,
            userId,
          })
        : Promise.reject(new Error("invalid token")),
  } as AuthService;
}

function characterCommand(timeZoneIdentifier: string) {
  return {
    commandId: "019c0123-4567-789a-8bcd-ef0123456790",
    expectedVersion: 0,
    operation: "upsert",
    parentId: null,
    payload: {
      card: {
        activityProfile: {
          focusDurationMinutes: 8,
          rhythm: "earlyBird",
          timeZoneIdentifier,
        },
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
        regionId: "london",
        speechStyle: "Friendly",
      },
      difficulty: "junior3",
      isFriend: true,
      isMainCharacter: true,
      metAt: "2026-09-10T00:00:00.000Z",
      schemaVersion: 2,
    },
    resourceId: "019c0123-4567-789a-8bcd-ef0123456791",
    resourceType: "character",
  };
}

describe("content routes", () => {
  it("仅接收已知旧会话字段，仍拒绝未知字段、错误类型及旧小测资源", async () => {
    const executeCommands = vi.fn<ContentService["executeCommands"]>(() =>
      Promise.resolve([]),
    );
    const app = await buildApp(loadConfig({ NODE_ENV: "test" }), { logger: false });
    registerContentRoutes(app, authService(), { executeCommands, getPage: vi.fn() });
    const command = {
      commandId: "019c0123-4567-789a-8bcd-ef0123456790",
      expectedVersion: 0,
      operation: "upsert",
      parentId: "019c0123-4567-789a-8bcd-ef0123456791",
      payload: {
        createdAt: "2026-10-01T00:00:00.000Z",
        isArchived: false,
        isEncounterSession: false,
        lastMessageAt: "2026-10-01T00:00:00.000Z",
        lastSummarizedMessageIndex: 0,
        quizOptOut: false,
        schemaVersion: 2,
        turnCount: 4,
        turnsSinceQuiz: 4,
      },
      resourceId: "019c0123-4567-789a-8bcd-ef0123456792",
      resourceType: "conversation",
    };
    try {
      for (const [candidate, expectedStatus] of [
        [command, 200],
        [{ ...command, payload: { ...command.payload, unknownField: true } }, 400],
        [{ ...command, payload: { ...command.payload, quizOptOut: "false" } }, 400],
        [{ ...command, resourceType: "quiz_record" }, 400],
      ] as const) {
        const response = await app.inject({
          method: "POST",
          url: "/v1/content/commands",
          headers: { authorization: "Bearer valid-access-token" },
          payload: { commands: [candidate] },
        });
        expect(response.statusCode).toBe(expectedStatus);
      }
      expect(executeCommands).toHaveBeenCalledTimes(1);
      expect(executeCommands.mock.calls[0]?.[1][0]).toMatchObject(command);
    } finally {
      await app.close();
    }
  });
  it("accepts and validates the NPC activity profile used by iOS sync", async () => {
    const executeCommands = vi.fn<ContentService["executeCommands"]>(() =>
      Promise.resolve([]),
    );
    const service = {
      executeCommands,
      getPage: vi.fn<ContentService["getPage"]>(),
    } satisfies ContentService;
    const app = await buildApp(loadConfig({ NODE_ENV: "test" }), {
      logger: false,
    });
    registerContentRoutes(app, authService(), service);

    const accepted = await app.inject({
      headers: { authorization: "Bearer valid-access-token" },
      method: "POST",
      payload: { commands: [characterCommand("Europe/London")] },
      url: "/v1/content/commands",
    });
    expect(accepted.statusCode).toBe(200);
    const submitted = executeCommands.mock.calls[0];
    expect(submitted?.[0]).toBe(userId);
    expect(submitted?.[1]).toHaveLength(1);
    expect(submitted?.[1][0]).toMatchObject({
      payload: {
        card: {
          activityProfile: {
            focusDurationMinutes: 8,
            rhythm: "earlyBird",
            timeZoneIdentifier: "Europe/London",
          },
        },
      },
    });

    const rejected = await app.inject({
      headers: { authorization: "Bearer valid-access-token" },
      method: "POST",
      payload: { commands: [characterCommand("Europe/Not-A-City")] },
      url: "/v1/content/commands",
    });
    expect(rejected.statusCode).toBe(400);
    expect(rejected.json<{ code: string }>().code).toBe("INVALID_REQUEST");
    expect(executeCommands).toHaveBeenCalledTimes(1);
    await app.close();
  });
  it("校验诊断只记录字段位置，不记录内容、未知键名或剧情标记", async () => {
    const app = await buildApp(loadConfig({ NODE_ENV: "test" }), { logger: false });
    const logged: unknown[] = [];
    app.addHook("onRequest", (request, _reply, done) => {
      request.log.warn = (...args: unknown[]) => {
        logged.push(args[0]);
      };
      done();
    });
    const executeCommands = vi.fn<ContentService["executeCommands"]>();
    registerContentRoutes(app, authService(), { executeCommands, getPage: vi.fn() });
    const command = characterCommand("SECRET_BAD_ZONE");
    const response = await app.inject({
      method: "POST",
      url: "/v1/content/commands",
      headers: { authorization: "Bearer valid-access-token" },
      payload: {
        commands: [
          {
            ...command,
            payload: {
              ...command.payload,
              SECRET_UNKNOWN_KEY: "SECRET_VALUE",
            },
          },
          {
            commandId: command.commandId,
            resourceId: "test_story",
            resourceType: "story_progress",
            operation: "upsert",
            expectedVersion: 0,
            payload: { schemaVersion: 1, flags: { SECRET_FLAG: "SECRET_TEXT" } },
          },
        ],
      },
    });
    expect(response.statusCode).toBe(400);
    expect(executeCommands).not.toHaveBeenCalled();
    const diagnostic = logged.find(
      (row) =>
        (row as { event?: string }).event === "content.command.validation_failed",
    );
    expect((diagnostic as { issues: unknown[] }).issues).toEqual(
      expect.arrayContaining([
        {
          code: "custom",
          path: [
            "commands",
            0,
            "payload",
            "card",
            "activityProfile",
            "timeZoneIdentifier",
          ],
        },
        {
          code: "unrecognized_keys",
          path: ["commands", 0, "payload"],
        },
        { code: "invalid_type", path: ["commands", 1, "payload", "flags", "<flag>"] },
      ]),
    );
    expect(JSON.stringify(diagnostic)).not.toContain("SECRET");
    await app.close();
  });
});
