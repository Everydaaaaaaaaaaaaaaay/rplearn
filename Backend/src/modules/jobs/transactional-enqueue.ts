import type { TransactionSql } from "postgres";
import type { PreparedJob } from "./types.js";

export async function insertPreparedJob(
  sql: TransactionSql,
  job: PreparedJob,
): Promise<void> {
  await sql`
    insert into app.jobs (
      id,
      user_id,
      type,
      status,
      unique_key,
      payload_ciphertext,
      nonce,
      tag,
      key_version,
      max_attempts,
      available_at
    )
    values (
      ${job.id},
      ${job.userId ?? null},
      ${job.type},
      'pending',
      ${job.uniqueKey ?? null},
      ${job.payloadCiphertext},
      ${job.nonce},
      ${job.tag},
      ${job.keyVersion},
      ${job.maxAttempts},
      ${job.availableAt.toISOString()}
    )
    on conflict (unique_key) where unique_key is not null do nothing
  `;
}
