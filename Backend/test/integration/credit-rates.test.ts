import Fastify from "fastify";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { integrationConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import {
  CreditRateRepository,
  applyCreditRate,
} from "../../src/modules/access/credit-rate-repository.js";
import { CreditRateService } from "../../src/modules/access/credit-rate-service.js";
import { registerCreditRateAdminRoutes } from "../../src/modules/access/credit-rate-admin-routes.js";
import { createAccessService } from "../../src/modules/access/service.js";
import { createCreditService } from "../../src/modules/access/credit-service.js";
import { createAdminAuthenticator } from "../../src/modules/admin/http.js";
import { newEntityId } from "../../src/shared/id.js";

const request = {
  task: "conversation",
  provider: "deepseek",
  model: "deepseek-v4-flash",
  messages: [{ role: "user" as const, content: "hello" }],
  maxOutputTokens: 100,
};
const usage = {
  inputTokens: 1000,
  cacheHitTokens: 0,
  cacheMissTokens: 1000,
  outputTokens: 100,
  totalTokens: 1100,
};

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "credit consumption rates",
  () => {
    let runtime: RuntimeDependencies;
    let rates: CreditRateService;
    let credits: ReturnType<typeof createCreditService>;
    const users = [newEntityId(), newEntityId(), newEntityId()] as const;
    const app = Fastify();
    const token = "credit-rate-test-token-long-enough-for-admin";
    async function change(
      scope: "global" | "users",
      rateUnits: number | null,
      userIds: string[] = [],
    ) {
      return rates.update(
        {
          scope,
          rateUnits,
          userIds,
          changeReason: "积分倍率集成测试",
          expectedVersion: (await rates.read()).version,
        },
        "test",
        newEntityId(),
      );
    }
    async function operation(
      user: string,
      task = "conversation",
      reason: string | null = null,
    ) {
      const id = newEntityId();
      await credits.reserve(user, id, id, { ...request, task });
      await credits.dispatch(user, id);
      await credits.finish(
        user,
        id,
        usage,
        { content: "hi" },
        "test-provider",
        request.model,
        reason,
      );
      const [row] = await runtime.database.sql<
        {
          settled_units: string;
          raw_settled_units: string;
          rate_units: number;
          billing_scope: string;
        }[]
      >`select settled_units::text,raw_settled_units::text,rate_units,billing_scope from app.credit_operations where user_id=${user} and operation_id=${id}`;
      return { id, row };
    }
    beforeAll(async () => {
      runtime = createRuntimeDependencies(
        integrationConfig({ ...process.env, NODE_ENV: "test" }),
      );
      await runMigrations(runtime.database);
      await runtime.start();
      rates = new CreditRateService(new CreditRateRepository(runtime.database));
      credits = createCreditService(runtime.database);
      for (const id of users)
        await runtime.database.sql`insert into app.users(id) values(${id})`;
      registerCreditRateAdminRoutes(
        app,
        createAdminAuthenticator([{ keyId: "test", token }]),
        rates,
      );
    });
    afterAll(async () => {
      {
        await change("global", 10000);
        for (const id of users)
          await runtime.database.sql`delete from app.users where id=${id}`;
        await runtime.close();
      }
      await app.close();
    });
    it("global, batch override, inheritance and actual cost are independent", async () => {
      await change("global", 1000);
      await change("users", 2500, users.slice(0, 2));
      for (let i = 0; i < users.length; i++) {
        const { row } = await operation(users[i] ?? users[0]);
        expect(row?.rate_units).toBe(i < 2 ? 2500 : 1000);
        expect(BigInt(row?.settled_units ?? "-1")).toBe(
          applyCreditRate(BigInt(row?.raw_settled_units ?? "-1"), i < 2 ? 2500 : 1000),
        );
      }
      await change("users", null, [users[0]]);
      expect((await operation(users[0])).row?.rate_units).toBe(1000);
    });
    it("pins the rate at reservation, including delayed reconciliation", async () => {
      const user = users[0];
      await change("users", 1000, [user]);
      const id = newEntityId();
      await credits.reserve(user, id, id, request);
      await change("users", 9000, [user]);
      await credits.dispatch(user, id);
      await credits.finish(user, id, null);
      await credits.reconcile(user, id, 12345n, "verified provider invoice for test");
      await credits.finish(user, id, usage);
      const [row] = await runtime.database
        .sql`select settled_units::text,raw_settled_units::text,rate_units from app.credit_operations where user_id=${user} and operation_id=${id}`;
      expect(row).toMatchObject({
        settled_units: "1235",
        raw_settled_units: "12345",
        rate_units: 1000,
      });
    });
    it("0x admits an exhausted user but never discounts automation or empty replies", async () => {
      const user = users[1];
      await runtime.database
        .sql`update app.credit_operations set settled_units=100000000000 where user_id=${user} and billing_scope='user'`;
      await change("users", 0, [user]);
      expect((await operation(user)).row?.settled_units).toBe("0");
      expect((await credits.snapshot(user)).consumptionMultiplier).toBe(0);
      await expect(
        createAccessService(runtime.database).reserveVoice(user, newEntityId()),
      ).resolves.toBeDefined();
      for (const [task, reason] of [
        ["coach_review", null],
        ["conversation", "AI_EMPTY_RESPONSE"],
      ] as const) {
        const { row } = await operation(user, task, reason);
        expect(row?.billing_scope).toBe("service");
        expect(row?.settled_units).toBe(row?.raw_settled_units);
        expect(Number(row?.settled_units)).toBeGreaterThan(0);
      }
    });
    it("audits, rejects stale writes, replays commands and rolls back an invalid batch", async () => {
      const input = {
        scope: "global",
        rateUnits: 5000,
        userIds: [],
        changeReason: "测试审计与并发版本",
        expectedVersion: (await rates.read()).version,
      };
      const command = newEntityId();
      const first = await rates.update(input, "test", command);
      expect(await rates.update(input, "test", command)).toEqual({
        ...first,
        replay: true,
      });
      await expect(
        rates.update({ ...input, rateUnits: 6000 }, "test", command),
      ).rejects.toMatchObject({ code: "IDEMPOTENCY_CONFLICT" });
      await expect(rates.update(input, "test", newEntityId())).rejects.toMatchObject({
        code: "VERSION_CONFLICT",
      });
      const before = await rates.read();
      await expect(change("users", 1, [users[0], newEntityId()])).rejects.toMatchObject(
        { code: "USER_NOT_FOUND" },
      );
      expect(await rates.read()).toEqual(before);
      expect(before.history[0]).toMatchObject({
        operatorKeyId: "test",
        reason: input.changeReason,
      });
    });
    it("requires admin auth and rejects malformed changes", async () => {
      expect(
        (await app.inject({ method: "GET", url: "/internal/admin/ai/credit-rates" }))
          .statusCode,
      ).toBe(401);
      const headers = {
        authorization: `Bearer ${token}`,
        "idempotency-key": newEntityId(),
      };
      expect(
        (
          await app.inject({
            method: "GET",
            url: "/internal/admin/ai/credit-rates",
            headers,
          })
        ).statusCode,
      ).toBe(200);
      for (const rateUnits of [-1, 1000001, 0.1, null]) {
        expect(
          (
            await app.inject({
              method: "PUT",
              url: "/internal/admin/ai/credit-rates",
              headers,
              payload: {
                scope: "global",
                userIds: [],
                rateUnits,
                changeReason: "invalid test",
                expectedVersion: (await rates.read()).version,
              },
            })
          ).statusCode,
        ).toBe(400);
      }
      const body = {
        scope: "users",
        userIds: [users[2]],
        rateUnits: 1000,
        changeReason: "后台路由保存验证",
        expectedVersion: (await rates.read()).version,
      };
      expect(
        (
          await app.inject({
            method: "PUT",
            url: "/internal/admin/ai/credit-rates",
            headers,
            payload: body,
          })
        ).statusCode,
      ).toBe(200);
    });
  },
);
