import { spawn } from "node:child_process";
import { createServer, type Server } from "node:http";
import type { AddressInfo } from "node:net";
import { resolve } from "node:path";
import { setTimeout as delay } from "node:timers/promises";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { loadConfig } from "../../src/config/env.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";

const runEndToEndTests = process.env.RUN_E2E_TESTS === "true";
const backendRoot = process.cwd();
const email = `e2e-${crypto.randomUUID()}@example.com`;
const password = "E2e-Secret-Password-42!";
const querySecret = "E2E_QUERY_CREDENTIAL_MUST_NOT_LEAK";
const profileSecret = "E2E_PRIVATE_PROFILE_MUST_NOT_LEAK";
const fakeSessionId = "9d7e1c2b-6f4a-4cf8-916b-c11ca3128fb1";

type TokenResponse = Readonly<{
  accessToken: string;
  refreshToken: string;
  sessionId: string;
  userId: string;
}>;

type ProfileSnapshot = Readonly<{
  profile: Readonly<{
    displayName: string | null;
    hasCompletedOnboarding: boolean;
    version: number;
  }>;
  tickets: readonly Readonly<{ id: string }>[];
}>;

function listen(server: Server): Promise<number> {
  return new Promise((resolvePort, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      server.off("error", reject);
      resolvePort((server.address() as AddressInfo).port);
    });
  });
}

function closeServer(server: Server): Promise<void> {
  return new Promise((resolveClose, reject) => {
    server.close((error) => {
      if (error === undefined) {
        resolveClose();
      } else {
        reject(error);
      }
    });
  });
}

async function availablePort(): Promise<number> {
  const server = createServer();
  const port = await listen(server);
  await closeServer(server);
  return port;
}

describe.runIf(runEndToEndTests)("compiled backend process", () => {
  let apiPort = 0;
  let child: ReturnType<typeof spawn> | undefined;
  let childOutput = "";
  let collector: Server;
  const tracePayloads: Buffer[] = [];
  let database: DatabaseResource;
  let userId: string | undefined;

  const appendOutput = (chunk: Buffer): void => {
    childOutput += chunk.toString("utf8");
    if (childOutput.length > 1_000_000) {
      childOutput = childOutput.slice(-1_000_000);
    }
  };

  const stopApi = async (): Promise<void> => {
    if (child?.exitCode !== null) {
      return;
    }
    const runningChild = child;
    await new Promise<void>((resolveExit, reject) => {
      const timeout = setTimeout(() => {
        runningChild.kill("SIGKILL");
        reject(new Error("The compiled API did not stop within its grace period"));
      }, 10_000);
      runningChild.once("exit", (code, signal) => {
        clearTimeout(timeout);
        if (code === 0 && signal === null) {
          resolveExit();
        } else {
          reject(
            new Error(
              `The compiled API exited abnormally (code=${String(code)}, signal=${String(signal)})`,
            ),
          );
        }
      });
      runningChild.kill("SIGTERM");
    });
  };

  beforeAll(async () => {
    const databaseUrl = process.env.DATABASE_URL;
    const redisUrl = process.env.REDIS_URL;
    if (databaseUrl === undefined || redisUrl === undefined) {
      throw new Error("The E2E database and Redis URLs are required");
    }
    database = createDatabase(
      loadConfig({
        DATABASE_URL: databaseUrl,
        NODE_ENV: "test",
        REDIS_URL: redisUrl,
      }),
    );
    await runMigrations(database);

    collector = createServer((request, response) => {
      void (async () => {
        if (request.method !== "POST" || request.url !== "/v1/traces") {
          response.statusCode = 404;
          response.end();
          return;
        }
        const chunks: Buffer[] = [];
        for await (const chunk of request) {
          chunks.push(Buffer.from(chunk as Uint8Array));
        }
        tracePayloads.push(Buffer.concat(chunks));
        response.statusCode = 200;
        response.setHeader("content-type", "application/x-protobuf");
        response.end();
      })().catch(() => {
        response.destroy();
      });
    });
    const collectorPort = await listen(collector);
    apiPort = await availablePort();

    child = spawn(
      process.execPath,
      [
        "--import",
        resolve(backendRoot, "dist/instrumentation-loader.js"),
        "--import",
        resolve(backendRoot, "dist/instrumentation.js"),
        resolve(backendRoot, "dist/server.js"),
      ],
      {
        cwd: backendRoot,
        env: {
          ...process.env,
          ADMIN_API_ENABLED: "false",
          APP_VERSION: "e2e-acceptance",
          APPLE_AUTH_ENABLED: "false",
          APPLE_BILLING_ENABLED: "false",
          DATABASE_URL: databaseUrl,
          DEEPSEEK_API_KEY: "",
          HOST: "127.0.0.1",
          LOG_LEVEL: "info",
          MEDIA_STORAGE_ENABLED: "false",
          NODE_ENV: "development",
          OTEL_EXPORTER_OTLP_HEADERS: "",
          OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: `http://127.0.0.1:${collectorPort.toString()}/v1/traces`,
          OTEL_EXPORTER_OTLP_TRACES_TIMEOUT: "2000",
          OTEL_SERVICE_NAME: "lingotrip-api-e2e",
          OTEL_TRACE_SAMPLE_RATIO: "1",
          OTEL_TRACING_ENABLED: "true",
          PORT: apiPort.toString(),
          REDIS_URL: redisUrl,
          SMTP_PASSWORD: "",
          SMTP_USER: "",
        },
        stdio: ["ignore", "pipe", "pipe"],
      },
    );
    child.stdout?.on("data", appendOutput);
    child.stderr?.on("data", appendOutput);

    for (let attempt = 1; attempt <= 100; attempt += 1) {
      if (child.exitCode !== null) {
        throw new Error(`The compiled API exited during startup\n${childOutput}`);
      }
      try {
        const response = await fetch(
          `http://127.0.0.1:${apiPort.toString()}/health/ready`,
        );
        if (response.ok) {
          return;
        }
      } catch {
        // The socket is expected to refuse connections while startup is in progress.
      }
      await delay(100);
    }
    throw new Error(`The compiled API did not become ready\n${childOutput}`);
  }, 20_000);

  afterAll(async () => {
    await stopApi().catch(() => undefined);
    if (userId !== undefined) {
      await database.sql`
        delete from app.jobs
        where user_id = ${userId}
      `;
      await database.sql`
        delete from app.audit_events
        where actor_user_id = ${userId}
      `;
      await database.sql`
        delete from app.users
        where id = ${userId}
      `;
    }
    await database.close();
    await closeServer(collector);
  });

  it("validates authentication, idempotent state, sync, and telemetry privacy", async () => {
    const baseUrl = `http://127.0.0.1:${apiPort.toString()}`;
    const registration = await fetch(`${baseUrl}/v1/auth/register`, {
      body: JSON.stringify({ email, password }),
      headers: { "content-type": "application/json" },
      method: "POST",
    });
    expect(registration.status).toBe(202);

    const verifiedUsers = await database.sql<{ user_id: string }[]>`
        update app.user_identities
        set email_verified_at = now()
        where provider = 'email'
          and provider_subject = ${email}
        returning user_id::text
      `;
    userId = verifiedUsers[0]?.user_id;
    expect(userId).toBeTypeOf("string");

    const login = await fetch(`${baseUrl}/v1/auth/login`, {
      body: JSON.stringify({
        device: {
          appVersion: "1.0-e2e",
          deviceId: "e2e-ios-device",
          deviceName: "E2E iPhone",
          platform: "ios",
        },
        email,
        password,
      }),
      headers: { "content-type": "application/json" },
      method: "POST",
    });
    expect(login.status).toBe(200);
    const tokens = (await login.json()) as TokenResponse;
    expect(tokens.userId).toBe(userId);
    const authorization = `Bearer ${tokens.accessToken}`;

    const initialSnapshotResponse = await fetch(`${baseUrl}/v1/me`, {
      headers: { authorization },
    });
    expect(initialSnapshotResponse.status).toBe(200);
    const initialSnapshot = (await initialSnapshotResponse.json()) as ProfileSnapshot;

    const profileCommandId = crypto.randomUUID();
    const profileRequest = {
      body: JSON.stringify({
        displayName: profileSecret,
        expectedVersion: initialSnapshot.profile.version,
        hasCompletedOnboarding: true,
      }),
      headers: {
        authorization,
        "content-type": "application/json",
        "idempotency-key": profileCommandId,
      },
      method: "PATCH",
    } as const;
    const profileUpdate = await fetch(`${baseUrl}/v1/me`, profileRequest);
    expect(profileUpdate.status).toBe(200);
    const updatedProfile: unknown = await profileUpdate.json();
    const profileReplay = await fetch(`${baseUrl}/v1/me`, profileRequest);
    expect(profileReplay.status).toBe(200);
    await expect(profileReplay.json()).resolves.toEqual(updatedProfile);

    const ticketCommandId = crypto.randomUUID();
    const ticketRequest = {
      headers: {
        authorization,
        "idempotency-key": ticketCommandId,
      },
      method: "POST",
    } as const;
    const ticketClaim = await fetch(
      `${baseUrl}/v1/progression/starter-ticket`,
      ticketRequest,
    );
    expect(ticketClaim.status).toBe(200);
    const claimedTicket: unknown = await ticketClaim.json();
    const ticketReplay = await fetch(
      `${baseUrl}/v1/progression/starter-ticket`,
      ticketRequest,
    );
    expect(ticketReplay.status).toBe(200);
    await expect(ticketReplay.json()).resolves.toEqual(claimedTicket);

    const authoritativeState = await fetch(`${baseUrl}/v1/me`, {
      headers: { authorization },
    });
    const state = (await authoritativeState.json()) as ProfileSnapshot;
    expect(state.profile).toMatchObject({
      displayName: profileSecret,
      hasCompletedOnboarding: true,
    });
    expect(state.tickets).toHaveLength(1);

    const syncSnapshot = await fetch(`${baseUrl}/v1/sync/snapshot`, {
      headers: { authorization },
    });
    expect(syncSnapshot.status).toBe(200);
    await expect(syncSnapshot.json()).resolves.toMatchObject({
      state: {
        profile: {
          displayName: profileSecret,
          hasCompletedOnboarding: true,
        },
      },
    });

    const sessionList = await fetch(
      `${baseUrl}/v1/auth/sessions?credential=${querySecret}`,
      { headers: { authorization } },
    );
    expect(sessionList.status).toBe(200);

    const dynamicRoute = await fetch(
      `${baseUrl}/v1/auth/sessions/${fakeSessionId}?credential=${querySecret}`,
      {
        headers: { authorization },
        method: "DELETE",
      },
    );
    expect(dynamicRoute.status).toBe(404);

    const refresh = await fetch(`${baseUrl}/v1/auth/refresh`, {
      body: JSON.stringify({ refreshToken: tokens.refreshToken }),
      headers: { "content-type": "application/json" },
      method: "POST",
    });
    expect(refresh.status).toBe(200);
    const rotated = (await refresh.json()) as TokenResponse;
    expect(rotated.refreshToken).not.toBe(tokens.refreshToken);

    const replay = await fetch(`${baseUrl}/v1/auth/refresh`, {
      body: JSON.stringify({ refreshToken: tokens.refreshToken }),
      headers: { "content-type": "application/json" },
      method: "POST",
    });
    expect(replay.status).toBe(401);
    await expect(replay.json()).resolves.toMatchObject({
      code: "REFRESH_TOKEN_REUSE_DETECTED",
    });

    await stopApi();
    expect(tracePayloads.length).toBeGreaterThan(0);
    const telemetry = Buffer.concat(tracePayloads).toString("utf8");
    const privateValues = [
      email,
      password,
      tokens.accessToken,
      tokens.refreshToken,
      rotated.refreshToken,
      querySecret,
      profileSecret,
      fakeSessionId,
    ];
    for (const privateValue of privateValues) {
      expect(telemetry).not.toContain(privateValue);
      expect(childOutput).not.toContain(privateValue);
    }
    expect(telemetry).toContain("/v1/auth/sessions/:id");
    expect(childOutput).toMatch(/"traceId":"[a-f0-9]{32}"/);
    expect(childOutput).toMatch(/"spanId":"[a-f0-9]{16}"/);
    expect(childOutput).toContain("/v1/auth/sessions/:id");
  }, 30_000);
});
