import { createHash, randomUUID } from "node:crypto";
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, mkdtempSync, rmSync } from "node:fs";
import { createServer, get, type Server } from "node:https";
import type { AddressInfo } from "node:net";
import { resolve, join } from "node:path";
import { tmpdir } from "node:os";
import type { FastifyInstance } from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { buildApp } from "../../src/app.js";
import { loadConfig } from "../../src/config/env.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import { registerAuthRoutes } from "../../src/modules/auth/routes.js";
import { createAuthService } from "../../src/modules/auth/service.js";
import { registerNpcRoutes } from "../../src/modules/npc/routes.js";
import { createNpcService } from "../../src/modules/npc/service.js";
import { importAvatarManifest } from "../../src/modules/npc/avatar-import.js";
import {
  avatarMatches,
  type AvatarCandidate,
} from "../../src/modules/npc/avatar-matcher.js";
import type {
  AvatarRequirements,
  PublicNpc,
  PublicNpcCard,
  AvatarProfile,
} from "../../src/modules/npc/types.js";
import { createTestJobWorker } from "../helpers/jobs.js";

interface Entry {
  id: string;
  key: string;
  image: string;
  status: string;
  observed: AvatarProfile & { tags: string[]; theme: string };
  review: {
    sha256: string;
    circlePass: boolean;
    backgroundPass: boolean;
    status: string;
  };
}
const enabled = process.env.RUN_NPC_LIBRARY_E2E === "true";
const library = resolve(process.cwd(), "../Assets/NPC/Library/v3");
const reportDir = process.env.NPC_REPORT_DIR;
const seeds = (process.env.NPC_E2E_SEEDS ?? "90601,90602,90603").split(",").map(Number);
const caseCount = Number(process.env.NPC_E2E_CASES ?? 240);
function required<T>(value: T | null | undefined): T {
  if (value === undefined || value === null) throw Error("Missing expected test value");
  return value;
}
function random(seed: number) {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function premise(
  age: number,
  gender: PublicNpcCard["gender"],
  index: number,
): PublicNpcCard {
  return {
    age,
    gender,
    appearance: "Provisional appearance; finalized from reviewed portrait.",
    background: `Collects local stories; narrative fixture ${String(index)}.`,
    birthday: null,
    hobbies: ["walking", "cooking"],
    hometown: null,
    languages: ["English"],
    name: `Test Traveler ${String(index)}`,
    nationality: required(["British", "Indian", "Brazilian", "Japanese"][index % 4]),
    occupation: required(
      ["teacher", "baker", "musician", "mechanic", "retired researcher"][index % 5],
    ),
    personaVoice: {
      anchorLines: ["Tell me more."],
      boundaries: ["respects privacy"],
      conversationalHabits: ["asks precise questions"],
      flaws: ["impatient"],
      values: ["curiosity"],
    },
    personality: "Curious and direct",
    regionId: "london",
    signature: null,
    speechStyle: null,
  };
}
describe.runIf(enabled)(
  "NPC library over HTTP, PostgreSQL, Redis and HTTPS image bytes",
  () => {
    let app: FastifyInstance;
    let dependencies: RuntimeDependencies;
    let assets: Server;
    let base: string;
    let temporary: string;
    let ca: Buffer;
    let candidates: AvatarCandidate[] = [];
    let entries: Entry[] = [];
    const users: string[] = [];
    const npcIds: string[] = [];
    const assetPaths = new Map<string, string>();
    const verification = new Map<string, string>();
    let catalogHash: string;
    const request = async (
      path: string,
      body?: unknown,
      token?: string,
      method = body === undefined ? "GET" : "POST",
    ) =>
      fetch(base + path, {
        method,
        headers: {
          "content-type": "application/json",
          ...(token ? { authorization: `Bearer ${token}` } : {}),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
      });
    const imageBytes = (url: string) =>
      new Promise<Buffer>((res, rej) => {
        get(url, { ca }, (r) => {
          if (r.statusCode !== 200) {
            r.resume();
            rej(Error(`Image HTTP ${String(r.statusCode)}`));
            return;
          }
          const chunks: Buffer[] = [];
          r.on("data", (c: Buffer) => chunks.push(c));
          r.on("end", () => res(Buffer.concat(chunks)));
          r.on("error", rej);
        }).on("error", rej);
      });
    beforeAll(async () => {
      if (!reportDir || !process.env.DATABASE_URL || !process.env.REDIS_URL)
        throw Error(
          "Explicit isolated database, Redis and NPC_REPORT_DIR are required",
        );
      const bytes = readFileSync(join(library, "catalog.json"));
      catalogHash = createHash("sha256").update(bytes).digest("hex");
      const catalog = JSON.parse(bytes.toString()) as {
        styleVersion: string;
        entries: Entry[];
      };
      entries = catalog.entries.filter((e) => e.status === "accepted");
      expect(entries.length).toBeGreaterThanOrEqual(
        Number(process.env.NPC_E2E_MIN_ACCEPTED ?? 100),
      );
      const config = loadConfig({ ...process.env, NODE_ENV: "test" });
      dependencies = createRuntimeDependencies(config);
      await runMigrations(dependencies.database);
      await dependencies.start();
      const [existing] = await dependencies.database.sql<
        { count: number }[]
      >`select count(*)::int as count from app.npc_avatars`;
      if (existing?.count !== 0)
        throw Error(
          "Use an empty isolated NPC database; never overwrite existing portraits",
        );
      temporary = mkdtempSync(join(tmpdir(), "npc-library-tls-"));
      execFileSync(
        "openssl",
        [
          "req",
          "-x509",
          "-newkey",
          "rsa:2048",
          "-nodes",
          "-keyout",
          join(temporary, "key.pem"),
          "-out",
          join(temporary, "cert.pem"),
          "-days",
          "1",
          "-subj",
          "/CN=localhost",
          "-addext",
          "subjectAltName=IP:127.0.0.1,DNS:localhost",
        ],
        { stdio: "ignore" },
      );
      ca = readFileSync(join(temporary, "cert.pem"));
      assets = createServer(
        { cert: ca, key: readFileSync(join(temporary, "key.pem")) },
        (req, res) => {
          const path = assetPaths.get(req.url ?? "");
          if (!path) {
            res.writeHead(404).end();
            return;
          }
          res.writeHead(200, { "content-type": "image/png" });
          res.end(readFileSync(path));
        },
      );
      await new Promise<void>((res, rej) => {
        assets.once("error", rej);
        assets.listen(0, "127.0.0.1", res);
      });
      const port = (assets.address() as AddressInfo).port;
      const avatars = entries.map((e) => {
        const image = readFileSync(join(library, e.image));
        const sha256 = createHash("sha256").update(image).digest("hex");
        expect(e.review).toMatchObject({
          sha256,
          circlePass: true,
          backgroundPass: true,
          status: "accepted",
        });
        expect(e.observed).not.toBeNull();
        const path = `/${e.key}-${sha256.slice(0, 16)}.png`;
        assetPaths.set(path, join(library, e.image));
        return {
          id: e.id,
          url: `https://127.0.0.1:${String(port)}${path}`,
          enabled: true,
          tags: e.observed.tags,
          profile: {
            ageMin: e.observed.ageMin,
            ageMax: e.observed.ageMax,
            gender: e.observed.gender,
            appearance: e.observed.appearance,
            styleVersion: catalog.styleVersion,
            sha256,
          },
        };
      });
      expect(
        await importAvatarManifest(dependencies.database, { version: 2, avatars }),
      ).toBe(entries.length);
      candidates = avatars.map((a) => ({
        id: a.id,
        imageUrl: a.url,
        tags: a.tags,
        profile: a.profile,
      }));
      const auth = await createAuthService(config, dependencies.database);
      app = await buildApp(config, { logger: false });
      registerAuthRoutes(app, auth);
      registerNpcRoutes(app, auth, createNpcService(dependencies.database));
      base = await app.listen({ host: "127.0.0.1", port: 0 });
    }, 30000);
    afterAll(async () => {
      // Setup can fail before assigning these resources.
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
      await app?.close();
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
      if (assets)
        await new Promise<void>((res, rej) =>
          assets.close((e) => (e ? rej(e) : res())),
        );
      // eslint-disable-next-line @typescript-eslint/no-unnecessary-condition
      if (dependencies) {
        for (const id of npcIds)
          await dependencies.database.sql`delete from app.public_npcs where id=${id}`;
        for (const user of users) {
          await dependencies.database
            .sql`delete from app.npc_avatar_match_events where user_id=${user}`;
          await dependencies.database.sql`delete from app.jobs where user_id=${user}`;
          await dependencies.database
            .sql`delete from app.auth_security_events where user_id=${user}`;
          await dependencies.database.sql`delete from app.users where id=${user}`;
        }
        for (const e of candidates)
          await dependencies.database.sql`delete from app.npc_avatars where id=${e.id}`;
        await dependencies.close();
      }
      if (temporary) rmSync(temporary, { recursive: true, force: true });
    }, 30000);
    for (const seed of seeds)
      it(`records coverage and persistent binding, seed ${String(seed)}`, async () => {
        const tokens: { token: string; userId: string; seen: Set<string> }[] = [];
        const config = loadConfig({ ...process.env, NODE_ENV: "test" });
        const worker = createTestJobWorker(config, dependencies.database, {
          sendEmailVerification: (email, token) => {
            verification.set(email, token);
            return Promise.resolve();
          },
          sendPasswordReset: () => Promise.resolve(),
        });
        for (let i = 0; i < 8; i++) {
          const email = `npc-e2e-${randomUUID()}@example.com`,
            password = "Npc-E2e-Secret-2026!";
          expect((await request("/v1/auth/register", { email, password })).status).toBe(
            202,
          );
          expect(await worker.runOnce()).toBe("succeeded");
          expect(
            (await request("/v1/auth/email/verify", { token: verification.get(email) }))
              .status,
          ).toBe(204);
          const login = await request("/v1/auth/login", {
            email,
            password,
            device: {
              deviceId: `npc-e2e-${String(seed)}-${String(i)}`,
              platform: "ios",
            },
          });
          expect(login.status).toBe(200);
          const t = (await login.json()) as { accessToken: string; userId: string };
          users.push(t.userId);
          tokens.push({ token: t.accessToken, userId: t.userId, seen: new Set() });
        }
        const rand = random(seed),
          pick = <T>(a: readonly T[]) => required(a[Math.floor(rand() * a.length)]);
        const cases: Record<string, unknown>[] = [];
        const gaps = new Map<
          string,
          {
            request: AvatarRequirements;
            count: number;
            reason: string;
            minCandidates: number;
          }
        >();
        let matched = 0;
        for (let i = 0; i < caseCount; i++) {
          const age = 14 + Math.floor(rand() * 72),
            gender = pick(["female", "male", "other"] as const);
          const requiredTags: string[] = [];
          if (rand() < 0.65)
            requiredTags.push(
              `theme:${pick(["blue", "red", "yellow", "violet", "jade"])}`,
            );
          if (i % 10 === 0)
            requiredTags.push(
              `body:${pick(["slim", "average", "full", "broad", "stocky"])}`,
            );
          if (i % 10 === 1)
            requiredTags.push(`facing:${pick(["front", "left", "right"])}`);
          if (i % 20 === 2)
            requiredTags.push(
              `expression:${pick(["joy", "concern", "calm", "surprise", "fatigue"])}`,
            );
          const requirements = { age, gender, requiredTags },
            viewer = required(tokens[i % tokens.length]),
            id = randomUUID(),
            card = premise(age, gender, i),
            payload = { id, card, requiredAvatarTags: requiredTags };
          npcIds.push(id);
          const response = await request("/v1/npcs", payload, viewer.token);
          const body = (await response.json()) as PublicNpc & { code?: string };
          const eligible = candidates.filter((c) => avatarMatches(c, requirements)),
            available = eligible.filter((c) => !viewer.seen.has(c.id));
          const [event] = await dependencies.database.sql<
            {
              reason: string;
              eligible_count: number;
              unseen_count: number;
              selected_avatar_id: string | null;
            }[]
          >`select reason,eligible_count,unseen_count,selected_avatar_id::text from app.npc_avatar_match_events where user_id=${viewer.userId} and npc_id=${id}`;
          expect(event?.eligible_count).toBe(eligible.length);
          expect(event?.unseen_count).toBe(available.length);
          let fetchedSha256: string | null = null;
          if (available.length) {
            expect(response.status).toBe(200);
            expect(body.avatar).not.toBeNull();
            const chosen = required(available.find((c) => c.id === body.avatar?.id));
            const profile = required(chosen.profile);
            const avatar = required(body.avatar);
            expect(chosen).toBeDefined();
            // Independent assertions prevent the production matcher being its own oracle.
            expect(profile.ageMin).toBeLessThanOrEqual(age);
            expect(profile.ageMax).toBeGreaterThanOrEqual(age);
            expect(profile.gender).toBe(gender);
            for (const tag of requiredTags) expect(chosen.tags).toContain(tag);
            expect(event?.selected_avatar_id).toBe(chosen.id);
            viewer.seen.add(chosen.id);
            matched++;
            expect(body.card).toEqual({
              ...card,
              appearance: profile.appearance,
            });
            for (const replayCard of [card, body.card]) {
              const replay = await request(
                "/v1/npcs",
                { ...payload, card: replayCard },
                viewer.token,
              );
              expect(replay.status).toBe(200);
              expect(await replay.json()).toEqual(body);
            }
            const lookup = await request(`/v1/npcs/by-traveler-id/${body.travelerId}`);
            expect(lookup.status).toBe(200);
            expect(await lookup.json()).toEqual(body);
            fetchedSha256 = createHash("sha256")
              .update(await imageBytes(avatar.url))
              .digest("hex");
            expect(fetchedSha256).toBe(profile.sha256);
          } else {
            expect(response.status).toBe(409);
            expect(body.code).toBe("NPC_AVATAR_COVERAGE_GAP");
            expect(event?.reason).toBe(
              eligible.length ? "user_pool_exhausted" : "coverage_gap",
            );
            const [stored] = await dependencies.database.sql<
              { count: number }[]
            >`select count(*)::int as count from app.public_npcs where id=${id}`;
            expect(stored?.count).toBe(0);
          }
          if (eligible.length < 3 || !available.length) {
            const reason = !eligible.length
              ? "coverage_gap"
              : !available.length
                ? "user_pool_exhausted"
                : "weak_depth";
            const key = JSON.stringify([
              Math.floor(age / 10),
              gender,
              requiredTags,
              reason,
            ]);
            const g = gaps.get(key);
            if (g) g.count++;
            else
              gaps.set(key, {
                request: requirements,
                count: 1,
                reason,
                minCandidates: eligible.length,
              });
          }
          cases.push({
            index: i,
            request: requirements,
            status: response.status,
            reason: event?.reason,
            eligibleCount: eligible.length,
            unseenCount: available.length,
            selectedAvatarId: body.avatar?.id ?? null,
            fetchedSha256,
          });
          mkdirSync(required(reportDir), { recursive: true });
          writeFileSync(
            join(required(reportDir), `checkpoint-${String(seed)}.json`),
            JSON.stringify(
              {
                seed,
                catalogSha256: catalogHash,
                accepted: entries.length,
                completedCases: cases.length,
                expectedCases: caseCount,
                cases,
              },
              null,
              2,
            ) + "\n",
          );
        }
        mkdirSync(required(reportDir), { recursive: true });
        writeFileSync(
          join(required(reportDir), `seed-${String(seed)}.json`),
          JSON.stringify(
            {
              seed,
              createdAt: new Date().toISOString(),
              accepted: entries.length,
              complete: true,
              expectedCases: caseCount,
              catalogSha256: catalogHash,
              cases,
              matched,
              gaps: [...gaps.values()],
              boundaries:
                "Synthetic narrative fixtures; real HTTP auth/registration/replay/lookup; real PostgreSQL+Redis; local HTTPS assets with verified certificate and SHA. Excludes live LLM, native UI and production CDN.",
            },
            null,
            2,
          ) + "\n",
        );
      }, 180000);
  },
);
