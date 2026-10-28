import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  contentHash,
  unitSchema,
  type LearningUnit,
} from "../../src/modules/learning/content.js";
import {
  LearningEngineRepository,
  type LearningSession,
} from "../../src/modules/learning/engine-repository.js";
import { loadExpansionCatalog } from "../../src/modules/learning/expansion-catalog.js";
import { expansionPublication } from "../../src/modules/learning/expansion-publication.js";
import { seniorPracticeCatalog } from "../../src/modules/learning/senior-practice-catalog.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "新原创的题型引用与实际曝光分开",
  () => {
    const catalog = loadExpansionCatalog("b039", false, "2026-10-28");
    const parent = catalog.units.find((u) => u.level === "senior1");
    if (!parent) throw new Error("Missing reviewed new senior parent");
    const publication = expansionPublication([parent]);
    const children = publication.admitted;
    const first = children.find((u) => u.originalGroup?.family === "shared_insertion");
    const sibling = children.find((u) => u.originalGroup?.family === "passage_form");
    if (!first || !sibling) throw new Error("Missing independent children");
    const selected = first,
      untouched = sibling,
      frozenParent = parent;
    const component = seniorPracticeCatalog().practices.find(
      (p) => p.unit.id === selected.id,
    )?.components[0];
    const originals = JSON.parse(
      readFileSync(
        new URL("../../config/learning/originals/catalog.json", import.meta.url),
        "utf8",
      ),
    ) as { units: { unit: unknown }[] };
    const original = originals.units
      .map((e) => unitSchema.parse(e.unit))
      .find((u) => u.id === component?.sourceUnitId);
    if (!original) throw new Error("Missing frozen task-format reference");
    const formatReference = original;
    const direct = loadExpansionCatalog("b017", false, "2026-10-28").units.find(
      (u) => u.level === "senior1",
    );
    if (!direct) throw new Error("Missing new unsplit senior practice");
    const directUnit = direct;
    const directRoot = direct.originalGroup?.sourceGroupIds[0]?.split("#")[0];
    const directOriginal = originals.units
      .map((e) => unitSchema.parse(e.unit))
      .find((u) => u.id === directRoot);
    if (!directOriginal) throw new Error("Missing direct format reference");
    const directReference = directOriginal;
    const users: string[] = [],
      inserted: string[] = [];
    let db: DatabaseResource, engine: LearningEngineRepository;
    beforeAll(async () => {
      db = createDatabase(integrationConfig());
      await runMigrations(db);
      engine = new LearningEngineRepository(db);
      const values = [
        ...publication.units,
        formatReference,
        directUnit,
        directReference,
      ];
      const existed = await db.sql<
        { id: string }[]
      >`select id from app.learning_units where id=any(${values.map((u) => u.id)})`;
      inserted.push(
        ...values.filter((u) => !existed.some((r) => r.id === u.id)).map((u) => u.id),
      );
      await engine.publishBatch(values);
    });
    afterAll(async () => {
      for (const id of users) await db.sql`delete from app.users where id=${id}`;
      for (const id of inserted) {
        await db.sql`delete from app.learning_unit_versions where unit_id=${id}`;
        await db.sql`delete from app.learning_units where id=${id}`;
      }
      await db.close();
    });
    async function account() {
      const user = randomUUID(),
        character = randomUUID();
      users.push(user);
      await db.sql`insert into app.users(id) values(${user})`;
      const command = <T>(action: (s: LearningSession) => Promise<T>) =>
        engine.command(user, randomUUID(), "availability-test", {}, action);
      await command((s) => s.ensureCharacter(character, "companion"));
      const fill = () =>
        command(async (s) =>
          s.debugFill(character, (await s.character(character)).cycleId),
        );
      const start = (id: string) =>
        command((s) =>
          s.start(character, "senior1", { completeGroups: true, originalUnitId: id }),
        );
      const historical = async (unit: LearningUnit) => {
        const state = await engine.read(user, (s) => s.character(character));
        const id = randomUUID();
        await db.sql`insert into app.learning_attempts(id,user_id,character_id,cycle_id,unit_id,unit_version,level_key,first_completed_at) values(${id},${user},${character},${state.cycleId},${unit.id},${unit.version},${unit.level},now())`;
        await db.sql`insert into app.learning_rounds(id,attempt_id,ordinal,question_ids,completed_at) values(${randomUUID()},${id},0,${unit.questions.map((q) => q.id)},now())`;
        await db.sql`update app.learning_characters set cycle_id=${randomUUID()} where user_id=${user} and character_id=${character}`;
        return id;
      };
      return { user, character, command, fill, start, historical };
    }
    it("旧格式源曝光后仍可抽全新子题，同组件不重抽且兄弟独立题保留", async () => {
      const a = await account();
      const old = await a.historical(formatReference);
      const before = contentHash(
        await db.sql`select unit_id,unit_version from app.learning_attempts where id=${old}`,
      );
      await a.fill();
      const first = await a.start(selected.id);
      expect(first.status).toBe("started");
      if (!first.attempt)
        throw new Error("New content was hidden by a format-only reference");
      expect(first.attempt.unit.id).toBe(selected.id);
      const attemptId = first.attempt.id;
      await a.command((s) => s.finish(attemptId, true));
      await a.fill();
      expect((await a.start(selected.id)).status).toBe("preparing");
      const second = await a.start(untouched.id);
      expect(second.status).toBe("started");
      expect(second.attempt?.unit.id).toBe(untouched.id);
      expect(
        contentHash(
          await db.sql`select unit_id,unit_version from app.learning_attempts where id=${old}`,
        ),
      ).toBe(before);
      const [frozen] = await db.sql<
        { payload: unknown }[]
      >`select payload from app.learning_unit_versions where unit_id=${selected.id} and version=${selected.version}`;
      expect(contentHash(frozen?.payload)).toBe(contentHash(selected));
    });
    it("不拆分的新28原创同样不被旧题型源曝光屏蔽", async () => {
      const a = await account();
      await a.historical(directReference);
      await a.fill();
      expect((await a.start(directUnit.id)).status).toBe("started");
    });
    it("真实新组合父题曝光仍阻止两个复用子题", async () => {
      const a = await account();
      await a.historical(frozenParent);
      await a.fill();
      expect((await a.start(selected.id)).status).toBe("preparing");
      expect((await a.start(untouched.id)).status).toBe("preparing");
    });
  },
);
