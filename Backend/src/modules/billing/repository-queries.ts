import type { DatabaseResource } from "../../db/client.js";
import type { StoreEnvironment } from "./types.js";

export async function findUserForOriginalTransaction(
  database: DatabaseResource,
  environment: StoreEnvironment,
  originalTransactionId: string,
): Promise<string | undefined> {
  const [row] = await database.sql<{ user_id: string | null }[]>`
    select user_id::text
    from app.subscriptions
    where provider = 'apple'
      and environment = ${environment}::app.billing_environment
      and original_transaction_id = ${originalTransactionId}
    union all
    select user_id::text from app.billing_transactions
    where provider='apple' and environment=${environment}::app.billing_environment
      and original_transaction_id=${originalTransactionId}
    limit 1
  `;
  return row?.user_id ?? undefined;
}

export async function activeBillingUserExists(
  database: DatabaseResource,
  userId: string,
): Promise<boolean> {
  const [row] = await database.sql<{ present: boolean }[]>`
    select exists (
      select 1
      from app.users
      where id = ${userId}
        and status = 'active'
    ) as present
  `;
  return row?.present ?? false;
}
