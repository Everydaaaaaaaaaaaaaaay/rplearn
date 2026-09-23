import { randomUUID } from "node:crypto";
import { beforeAll, afterAll, describe, it, expect } from "vitest";
import { integrationConfig } from "../helpers/integration.js";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createLearningService,
  type LearningService,
} from "../../src/modules/learning/service.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "learning durable state",
  () => {
    let db: DatabaseResource, service: LearningService;
    const first = randomUUID(),
      second = randomUUID();
    const payload = JSON.stringify({
      enabled: true,
      ledger: { version: 1, ruleRevision: 4 },
      listening: [],
      pending: [],
    });
    beforeAll(async () => {
      db = createDatabase(integrationConfig());
      await runMigrations(db);
      await db.sql`insert into app.users(id) values (${first}), (${second})`;
      service = createLearningService(db);
    });
    afterAll(async () => {
      await db.sql`delete from app.users where id in (${first},${second})`;
      await db.close();
    });
    it("isolates accounts, compares revisions atomically and cascades deletion", async () => {
      expect(await service.read(first)).toEqual({ revision: 0, payload: null });
      expect(await service.save(first, 0, payload)).toEqual({ revision: 1, payload });
      expect(await service.read(second)).toEqual({ revision: 0, payload: null });
      await expect(service.save(first, 0, payload)).rejects.toMatchObject({
        code: "LEARNING_STATE_CONFLICT",
      });
      const race = await Promise.allSettled([
        service.save(first, 1, payload),
        service.save(first, 1, payload),
      ]);
      expect(race.filter((x) => x.status === "fulfilled")).toHaveLength(1);
      expect((await service.read(first)).revision).toBe(2);
      await db.sql`delete from app.users where id=${first}`;
      expect(await service.read(first)).toEqual({ revision: 0, payload: null });
    });
  },
);
