import type { TransactionSql } from "postgres";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";

export const RATE_SCALE = 10000;
export function applyCreditRate(units: bigint, rate: number): bigint {
  return (units * BigInt(rate) + BigInt(RATE_SCALE - 1)) / BigInt(RATE_SCALE);
}
export async function effectiveCreditRate(sql: TransactionSql, userId: string) {
  const [row] = await sql<{ rate: number; auxiliaryRate: number; version: number }[]>`
    select coalesce(o.rate_units,p.rate_units) as rate,p.auxiliary_rate_units as "auxiliaryRate",p.version
    from app.credit_rate_policy p left join app.credit_rate_overrides o on o.user_id=${userId}
    where p.singleton=true`;
  if (!row) throw new Error("Missing credit rate policy");
  return row;
}
export interface CreditRateChange {
  expectedVersion: number;
  scope: "global" | "users" | "auxiliary";
  userIds: string[];
  rateUnits: number | null;
  changeReason: string;
}
export class CreditRateRepository {
  constructor(private readonly database: DatabaseResource) {}

  async read() {
    return this.database.sql.begin(async (sql) => {
      const [policy] = await sql<
        { version: number; rate_units: number; auxiliary_rate_units: number }[]
      >`
        select version,rate_units,auxiliary_rate_units from app.credit_rate_policy where singleton=true for share`;
      if (!policy) throw new Error("Missing credit rate policy");
      const overrides = await sql<{ userId: string; rateUnits: number }[]>`
        select user_id::text as "userId",rate_units as "rateUnits" from app.credit_rate_overrides order by user_id`;
      const history = await sql`
        select version,operator_key_id as "operatorKeyId",reason,request,previous,changed_at as "changedAt"
        from app.credit_rate_changes order by version desc limit 20`;
      return {
        version: policy.version,
        globalRateUnits: policy.rate_units,
        auxiliaryRateUnits: policy.auxiliary_rate_units,
        overrides,
        history,
      };
    });
  }

  async update(change: CreditRateChange, operator: string, commandId: string) {
    return this.database.sql.begin(async (sql) => {
      const [policy] = await sql<
        { version: number; rate_units: number; auxiliary_rate_units: number }[]
      >`
        select version,rate_units,auxiliary_rate_units from app.credit_rate_policy where singleton=true for update`;
      if (!policy) throw new Error("Missing credit rate policy");
      const payload = JSON.stringify(change);
      const [old] = await sql<
        { matches: boolean; version: number; operator_key_id: string }[]
      >`
        select request=${payload}::jsonb as matches,version,operator_key_id
        from app.credit_rate_changes where command_id=${commandId}`;
      if (old) {
        if (!old.matches || old.operator_key_id !== operator)
          throw new AppError({
            code: "IDEMPOTENCY_CONFLICT",
            message: "此操作编号已用于其他修改。",
            statusCode: 409,
          });
        return { version: old.version, replay: true };
      }
      if (policy.version !== change.expectedVersion)
        throw new AppError({
          code: "VERSION_CONFLICT",
          message: "倍率已被修改，请刷新后重试。",
          statusCode: 409,
        });
      let previous: unknown = { rateUnits: policy.rate_units };
      if (change.scope === "global") {
        await sql`update app.credit_rate_policy set rate_units=${change.rateUnits} where singleton=true`;
      } else if (change.scope === "auxiliary") {
        previous = { rateUnits: policy.auxiliary_rate_units };
        await sql`update app.credit_rate_policy set auxiliary_rate_units=${change.rateUnits} where singleton=true`;
      } else {
        const users =
          await sql`select id from app.users where id in ${sql(change.userIds)}`;
        if (users.length !== change.userIds.length)
          throw new AppError({
            code: "USER_NOT_FOUND",
            message: "包含不存在的用户，本次未修改任何倍率。",
            statusCode: 400,
          });
        previous =
          await sql`select user_id::text as "userId",rate_units as "rateUnits" from app.credit_rate_overrides where user_id in ${sql(change.userIds)}`;
        if (change.rateUnits === null) {
          await sql`delete from app.credit_rate_overrides where user_id in ${sql(change.userIds)}`;
        } else {
          for (const userId of change.userIds)
            await sql`
            insert into app.credit_rate_overrides(user_id,rate_units) values(${userId},${change.rateUnits})
            on conflict(user_id) do update set rate_units=excluded.rate_units,updated_at=now()`;
        }
      }
      const version = policy.version + 1;
      await sql`update app.credit_rate_policy set version=${version} where singleton=true`;
      await sql`insert into app.credit_rate_changes(command_id,version,operator_key_id,reason,request,previous)
        values(${commandId},${version},${operator},${change.changeReason},${payload}::jsonb,${JSON.stringify(previous)}::jsonb)`;
      return { version, replay: false };
    });
  }
}
