import "dotenv/config";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { createCreditService } from "../modules/access/credit-service.js";
import { decimalUnits } from "../modules/access/credit-pricing.js";

async function main(): Promise<void> {
  const database = createDatabase(loadConfig());
  try {
    const [command, userId, operationId, cny, evidence] = process.argv.slice(2);
    if (command === "reconcile") {
      if (!userId || !operationId || !cny || !evidence)
        throw new Error(
          'Usage: credit-ledger reconcile USER_UUID OPERATION_UUID CNY "provider billing evidence"',
        );
      await createCreditService(database).reconcile(
        userId,
        operationId,
        decimalUnits(cny, 9),
        evidence,
      );
      process.stdout.write("Reconciled one operation.\n");
    } else if (command === "report") {
      const summary =
        await database.sql`select plan,billing_scope,task,price->>'provider' as provider,price->>'model' as model,price->>'version' as price_version,status,
        count(*)::int as calls,count(distinct user_id)::int as users,
        sum(settled_units)::text as settled_nanoyuan,sum(reserved_units) filter(where status in ('pending','dispatched','reserved'))::text as held_nanoyuan
        from app.credit_operations group by plan,billing_scope,task,price->>'provider',price->>'model',price->>'version',status order by plan,billing_scope,task,status`;
      const pending =
        await database.sql`select user_id::text,operation_id::text,billing_scope,task,provider_request_id,price,reserved_units::text,reason,created_at
        from app.credit_operations where status='pending' or (status='dispatched' and expires_at<=now()) order by created_at limit 1000`;
      process.stdout.write(
        JSON.stringify(
          {
            currency: "CNY",
            unitsPerYuan: "1000000000",
            note: "Settled token costs use provider usage and the saved price. Pending costs are unknown; hosting, taxes and other operating costs are excluded.",
            summary,
            pending,
          },
          null,
          2,
        ) + "\n",
      );
    } else throw new Error("Use credit-ledger report or reconcile");
  } finally {
    await database.close();
  }
}
void main().catch((error: unknown) => {
  process.stderr.write(
    `${error instanceof Error ? error.message : "Credit ledger failed"}\n`,
  );
  process.exitCode = 1;
});
