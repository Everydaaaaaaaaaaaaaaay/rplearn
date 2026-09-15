import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { CreditRateRepository } from "../../src/modules/access/credit-rate-repository.js";
import { CreditRateService } from "../../src/modules/access/credit-rate-service.js";
import { createCreditService } from "../../src/modules/access/credit-service.js";
import { newEntityId } from "../../src/shared/id.js";
import { integrationConfig } from "../helpers/integration.js";

const request = {
  task: "coach_review",
  provider: "deepseek",
  model: "deepseek-v4-flash",
  messages: [{ role: "user" as const, content: "hello" }],
  maxOutputTokens: 100,
};

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "辅助任务标准倍率配置",
  () => {
    let database: DatabaseResource;
    let rates: CreditRateService;
    const user = newEntityId();
    const historyOperation = newEntityId();
    beforeAll(async () => {
      database = createDatabase(integrationConfig(process.env));
      await runMigrations(database);
      rates = new CreditRateService(new CreditRateRepository(database));
      await database.sql`insert into app.users(id) values(${user})`;
    });
    afterAll(async () => {
      await database.close();
    });

    it("旧预算耗尽后可按 0.01 倍继续，恢复后重新限制，历史账本不变", async () => {
      const credits = createCreditService(database);
      expect((await rates.read()).auxiliaryRateUnits).toBe(10000);
      await credits.reserve(user, historyOperation, historyOperation, request);
      await credits.finish(
        user,
        historyOperation,
        { inputTokens: 100, outputTokens: 10, totalTokens: 110 },
        null,
        null,
        request.model,
      );
      await database.sql`update app.credit_operations set status='settled',settled_units=80000000,raw_settled_units=80000000 where operation_id=${historyOperation}`;
      const userBefore = await credits.snapshot(user);
      const blocked = newEntityId();
      await expect(
        credits.reserve(user, blocked, blocked, request),
      ).rejects.toMatchObject({ code: "AUXILIARY_BUDGET_EXHAUSTED" });
      const policy = await rates.read();
      const change = {
        scope: "auxiliary",
        userIds: [],
        rateUnits: 100,
        expectedVersion: policy.version,
        changeReason: "测试期辅助预算临时调整",
      };
      const command = newEntityId();
      const saved = await rates.update(change, "test", command);
      expect(await rates.update(change, "test", command)).toEqual({
        ...saved,
        replay: true,
      });
      await expect(
        rates.update({ ...change, rateUnits: 200 }, "test", newEntityId()),
      ).rejects.toMatchObject({ code: "VERSION_CONFLICT" });
      const after = await rates.read();
      expect(after.globalRateUnits).toBe(policy.globalRateUnits);
      expect(after.auxiliaryRateUnits).toBe(100);
      expect(after.history[0]?.previous).toEqual({ rateUnits: 10000 });
      const allowed = newEntityId();
      await expect(
        credits.reserve(user, allowed, allowed, request),
      ).resolves.toMatchObject({ replay: false });
      expect(await credits.snapshot(user)).toEqual(userBefore);
      const [history] =
        await database.sql`select settled_units::text as settled,raw_settled_units::text as raw from app.credit_operations where operation_id=${historyOperation}`;
      expect(history).toEqual({ settled: "80000000", raw: "80000000" });
      // 在途金额也必须参与折算，不能通过并发预留绕过预算。
      await database.sql`update app.credit_operations set reserved_units=8000000000 where operation_id=${allowed}`;
      const pending = newEntityId();
      await expect(
        credits.reserve(user, pending, pending, request),
      ).rejects.toMatchObject({ code: "AUXILIARY_BUDGET_EXHAUSTED" });
      await rates.update(
        { ...change, rateUnits: 10000, expectedVersion: after.version },
        "test",
        newEntityId(),
      );
      const restored = newEntityId();
      await expect(
        credits.reserve(user, restored, restored, request),
      ).rejects.toMatchObject({ code: "AUXILIARY_BUDGET_EXHAUSTED" });
    });

    it("拒绝辅助倍率清空或夹带用户覆盖，允许标准的零倍率", async () => {
      const policy = await rates.read();
      const input = {
        scope: "auxiliary",
        userIds: [],
        rateUnits: 0,
        expectedVersion: policy.version,
        changeReason: "辅助倍率参数验证",
      };
      for (const invalid of [
        { ...input, rateUnits: null },
        { ...input, userIds: [user] },
        { ...input, rateUnits: -1 },
      ]) {
        expect(() => rates.update(invalid, "test", newEntityId())).toThrow();
      }
      await rates.update(input, "test", newEntityId());
      const id = newEntityId();
      await expect(
        createCreditService(database).reserve(user, id, id, request),
      ).resolves.toMatchObject({ replay: false });
    });
  },
);
