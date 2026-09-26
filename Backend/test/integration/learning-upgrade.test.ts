import { randomUUID } from "node:crypto";
import { cp, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { migrate } from "drizzle-orm/postgres-js/migrator";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { assertMigrationsCurrent, runMigrations } from "../../src/db/migrate.js";
import { integrationConfig } from "../helpers/integration.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "旧学习数据定向清理升级",
  () => {
    let admin: DatabaseResource | undefined;
    let database: DatabaseResource | undefined;
    let directory: string | undefined;
    let databaseName: string | undefined;
    beforeAll(async () => {
      const config = integrationConfig();
      const url = new URL(config.databaseUrl);
      databaseName = `${url.pathname.slice(1)}_upgrade`;
      // integrationConfig 已强制本机测试库前缀；仅创建并回收本测试拥有的库。
      admin = createDatabase(config);
      await admin.sql`create database ${admin.sql(databaseName)}`;
      url.pathname = `/${databaseName}`;
      database = createDatabase({ ...config, databaseUrl: url.toString() });
      directory = await mkdtemp(join(tmpdir(), "lingotrip-learning-upgrade-"));
      const source = fileURLToPath(new URL("../../migrations", import.meta.url));
      await cp(source, directory, { recursive: true });
      const journalPath = join(directory, "meta", "_journal.json");
      const journal = JSON.parse(await readFile(journalPath, "utf8")) as {
        entries: { idx: number }[];
      };
      journal.entries = journal.entries.filter((entry) => entry.idx <= 31);
      await writeFile(journalPath, JSON.stringify(journal));
      await migrate(database.database, { migrationsFolder: directory });
    });
    afterAll(async () => {
      await database?.close();
      if (admin && databaseName)
        await admin.sql`drop database ${admin.sql(databaseName)}`;
      await admin?.close();
      if (directory) await rm(directory, { recursive: true, force: true });
    });
    it("删除六张旧学习表，完整保留聊天、档案、角色、收藏和剧情", async () => {
      if (!database) throw new Error("升级测试数据库未启动。");
      const sql = database.sql;
      const user = randomUUID();
      const character = randomUUID();
      const conversation = randomUUID();
      const message = randomUUID();
      await sql`insert into app.users(id) values(${user})`;
      await sql`insert into app.user_profiles(user_id,difficulty,display_name) values(${user},'senior2','保留档案')`;
      const records = [
        {
          type: "character",
          id: character,
          parent: null,
          payload: { relationship: { affinity: 28 }, note: "保留角色" },
        },
        {
          type: "conversation",
          id: conversation,
          parent: character,
          payload: { note: "保留会话" },
        },
        {
          type: "message",
          id: message,
          parent: conversation,
          payload: { text: "保留消息" },
        },
        {
          type: "favorite",
          id: randomUUID(),
          parent: null,
          payload: { sentence: "保留收藏" },
        },
        {
          type: "story_progress",
          id: randomUUID(),
          parent: null,
          payload: { completedAt: "2026-09-26T00:00:00Z", note: "保留剧情" },
        },
      ];
      for (const record of records)
        await sql`insert into app.content_records(user_id,resource_type,resource_id,parent_id,payload)
      values(${user},${record.type},${record.id},${record.parent},${JSON.stringify(record.payload)}::jsonb)`;
      await sql`insert into app.learning_states(user_id,payload) values(${user},'旧学习专属记录')`;
      await sql`insert into app.unit_learning_accounts(user_id) values(${user})`;
      await sql`insert into app.unit_learning_characters(user_id,character_id,role_key) values(${user},${character},'oliver')`;
      await sql`insert into app.unit_learning_messages(user_id,message_id,character_id,character_count) values(${user},${message},${character},1000)`;
      await sql`insert into app.unit_learning_templates(id,role_key,grade,source,payload) values('old.unit','oliver',1,'authored','{}')`;
      await sql`insert into app.unit_learning_attempts(id,user_id,character_id,template_id,grade) values(${randomUUID()},${user},${character},'old.unit',1)`;
      const profileBefore =
        await sql`select to_jsonb(p)-'quiz_globally_enabled' as profile from app.user_profiles p where user_id=${user}`;
      const contentBefore =
        await sql`select * from app.content_records where user_id=${user} order by resource_id`;
      const retiredQuizId = randomUUID();
      await sql`insert into app.content_records(user_id,resource_type,resource_id,payload) values(${user},'quiz_record',${retiredQuizId},'{}')`;
      await sql`update app.content_records set payload=payload || '{"quizJson":"旧附加小测","quizChosenIndex":1}'::jsonb where user_id=${user} and resource_id=${message}`;
      await sql`update app.content_records set payload=payload || '{"quizOptOut":false,"turnsSinceQuiz":8}'::jsonb where user_id=${user} and resource_id=${conversation}`;
      const retiredEvent = {
        resourceType: "quiz_record",
        resourceId: retiredQuizId,
        payload: { question: "旧题" },
      };
      const retainedEvent = {
        resourceType: "message",
        resourceId: message,
        payload: { text: "保留消息", quizJson: "旧附加小测" },
      };
      for (const [index, payload] of [retiredEvent, retainedEvent].entries()) {
        const commandId = randomUUID();
        await sql`insert into app.sync_changes(user_id,command_id,event_id,event_type,sequence,payload) values(${user},${commandId},${randomUUID()},'content.test',${index + 1},${JSON.stringify(payload)}::jsonb)`;
        await sql`insert into app.command_receipts(user_id,command_id,route,request_hash,response) values(${user},${commandId},'content.command','test',${JSON.stringify(payload)}::jsonb)`;
      }
      await runMigrations(database);
      await assertMigrationsCurrent(database);
      for (const name of [
        "learning_states",
        "unit_learning_accounts",
        "unit_learning_characters",
        "unit_learning_messages",
        "unit_learning_templates",
        "unit_learning_attempts",
      ]) {
        const [table] = await sql<
          { relation: string | null }[]
        >`select to_regclass(${`app.${name}`})::text as relation`;
        expect(table?.relation).toBeNull();
      }
      expect(
        await sql`select to_jsonb(p)-'quiz_globally_enabled' as profile from app.user_profiles p where user_id=${user}`,
      ).toEqual(profileBefore);
      expect(
        await sql`select * from app.content_records where user_id=${user} order by resource_id`,
      ).toEqual(contentBefore);
      const events = await sql<
        { payload: unknown }[]
      >`select payload from app.sync_changes where user_id=${user}`;
      expect(events).toEqual([
        {
          payload: {
            resourceType: "message",
            resourceId: message,
            payload: { text: "保留消息" },
          },
        },
      ]);
      const receipts = await sql<
        { response: unknown }[]
      >`select response from app.command_receipts where user_id=${user}`;
      expect(receipts).toEqual([{ response: events[0]?.payload }]);
      const columns =
        await sql`select column_name from information_schema.columns where table_schema='app' and table_name='user_profiles' and column_name='quiz_globally_enabled'`;
      expect(columns).toHaveLength(0);
      expect(
        await sql`select * from app.learning_attempts where user_id=${user}`,
      ).toHaveLength(0);
      expect(
        await sql`select * from app.learning_level_progress where user_id=${user}`,
      ).toHaveLength(0);
    });
  },
);
