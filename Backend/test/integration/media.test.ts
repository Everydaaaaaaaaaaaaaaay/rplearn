import { createHash } from "node:crypto";
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
import { createMediaObjectStore } from "../../src/modules/media/object-store.js";
import { registerMediaRoutes } from "../../src/modules/media/routes.js";
import { createMediaService } from "../../src/modules/media/service.js";
import type { MediaUploadReservation } from "../../src/modules/media/types.js";
import { newEntityId } from "../../src/shared/id.js";
import { createTestJobWorker } from "../helpers/jobs.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

type TokenResponse = Readonly<{
  accessToken: string;
  userId: string;
}>;

describe.runIf(runIntegrationTests)("private user media", () => {
  let app: FastifyInstance;
  let dependencies: RuntimeDependencies;
  let accessToken: string;
  let userId: string;
  let worker: ReturnType<typeof createTestJobWorker>;
  const email = `media-${newEntityId()}@example.com`;
  const password = "Correct Horse Media 1!";
  const verificationTokens = new Map<string, string>();
  const assetId = newEntityId();
  const messageId = newEntityId();
  const bytes = Buffer.from("lingotrip-private-voice-fixture", "utf8");
  const checksumSha256 = createHash("sha256").update(bytes).digest("base64");

  beforeAll(async () => {
    const config = loadConfig({
      MEDIA_S3_ACCESS_KEY_ID: "lingotrip_dev",
      MEDIA_S3_BUCKET: "lingotrip-media-dev",
      MEDIA_S3_ENDPOINT: "http://127.0.0.1:9000",
      MEDIA_S3_FORCE_PATH_STYLE: "true",
      MEDIA_S3_REGION: "us-east-1",
      MEDIA_S3_SECRET_ACCESS_KEY: "lingotrip_dev_only",
      MEDIA_STORAGE_ENABLED: "true",
      NODE_ENV: "test",
    });
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
    const objectStore = createMediaObjectStore(config);
    const mediaService = createMediaService(config, dependencies.database, objectStore);
    worker = createTestJobWorker(config, dependencies.database, notifier, {
      processMediaDelete: mediaService.processDeletion,
    });
    app = await buildApp(config, { logger: false });
    registerAuthRoutes(app, authService);
    registerMediaRoutes(app, authService, mediaService);

    await app.inject({
      method: "POST",
      payload: { email, password },
      url: "/v1/auth/register",
    });
    expect(await worker.runOnce()).toBe("succeeded");
    await app.inject({
      method: "POST",
      payload: { token: verificationTokens.get(email) },
      url: "/v1/auth/email/verify",
    });
    const login = await app.inject({
      method: "POST",
      payload: {
        device: {
          deviceId: "media-test-device",
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

  it("uploads, verifies, downloads, protects references, and deletes asynchronously", async () => {
    const authorization = { authorization: `Bearer ${accessToken}` };
    const reservationPayload = {
      assetId,
      byteSize: bytes.byteLength,
      checksumSha256,
      contentType: "audio/x-caf",
      purpose: "voice_message",
    };
    const reservation = await app.inject({
      headers: authorization,
      method: "POST",
      payload: reservationPayload,
      url: "/v1/media/assets",
    });
    expect(reservation.statusCode).toBe(200);
    expect(reservation.headers["cache-control"]).toBe("no-store");
    const reserved = reservation.json<MediaUploadReservation>();
    expect(reserved.asset.status).toBe("pending");
    expect(reserved.upload?.method).toBe("PUT");
    if (reserved.upload === null) {
      throw new Error("The media fixture did not receive an upload URL");
    }

    const replay = await app.inject({
      headers: authorization,
      method: "POST",
      payload: reservationPayload,
      url: "/v1/media/assets",
    });
    expect(replay.json<MediaUploadReservation>().asset.id).toBe(assetId);

    const upload = await fetch(reserved.upload.url, {
      body: bytes,
      headers: reserved.upload.headers,
      method: "PUT",
    });
    expect(upload.status, await upload.text()).toBe(200);

    const completion = await app.inject({
      headers: authorization,
      method: "POST",
      url: `/v1/media/assets/${assetId}/complete`,
    });
    expect(completion.statusCode).toBe(200);
    expect(completion.json<{ status: string }>().status).toBe("ready");

    const readyReplay = await app.inject({
      headers: authorization,
      method: "POST",
      payload: reservationPayload,
      url: "/v1/media/assets",
    });
    expect(readyReplay.json<MediaUploadReservation>().upload).toBeNull();

    const download = await app.inject({
      headers: authorization,
      method: "GET",
      url: `/v1/media/assets/${assetId}`,
    });
    expect(download.statusCode).toBe(200);
    const downloadUrl = download.json<{ download: { url: string } }>().download.url;
    const downloaded = await fetch(downloadUrl);
    expect(downloaded.status).toBe(200);
    expect(Buffer.from(await downloaded.arrayBuffer())).toEqual(bytes);

    const contentPayload = JSON.stringify({ audioAssetId: assetId });
    await dependencies.database.sql`
      insert into app.content_records (
        user_id,
        resource_type,
        resource_id,
        parent_id,
        payload
      )
      values (
        ${userId},
        'message',
        ${messageId},
        null,
        ${contentPayload}::jsonb
      )
    `;
    const referencedDeletion = await app.inject({
      headers: authorization,
      method: "DELETE",
      url: `/v1/media/assets/${assetId}`,
    });
    expect(referencedDeletion.statusCode).toBe(409);
    expect(referencedDeletion.json<{ code: string }>().code).toBe("MEDIA_ASSET_IN_USE");

    await dependencies.database.sql`
      delete from app.content_records
      where user_id = ${userId}
        and resource_type = 'message'
        and resource_id = ${messageId}
    `;
    const deletion = await app.inject({
      headers: authorization,
      method: "DELETE",
      url: `/v1/media/assets/${assetId}`,
    });
    expect(deletion.statusCode).toBe(204);
    expect(await worker.runOnce()).toBe("succeeded");
    expect((await fetch(downloadUrl)).status).toBe(404);
  });
});
