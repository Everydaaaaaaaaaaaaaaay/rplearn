import type { DatabaseResource } from "../../db/client.js";
import type { ClaimedJob } from "./types.js";

export type JobFailureResult = "dead" | "retry_scheduled" | "lease_lost";

export class JobRepository {
  constructor(private readonly resource: DatabaseResource) {}

  async claim(
    workerId: string,
    now: Date,
    leaseSeconds: number,
  ): Promise<ClaimedJob | undefined> {
    return this.resource.sql.begin(async (sql) => {
      const [job] = await sql<
        {
          attempts: number;
          id: string;
          key_version: string;
          max_attempts: number;
          nonce: Buffer;
          payload_ciphertext: Buffer;
          tag: Buffer;
          type: string;
        }[]
      >`
        with candidate as (
          select id
          from app.jobs
          where (
              status = 'pending'
              and available_at <= ${now.toISOString()}
            )
            or (
              status = 'running'
              and lease_expires_at <= ${now.toISOString()}
            )
          order by available_at asc, created_at asc
          for update skip locked
          limit 1
        )
        update app.jobs j
        set status = 'running',
            attempts = j.attempts + 1,
            locked_by = ${workerId},
            lease_expires_at =
              ${now.toISOString()}::timestamptz +
              (${leaseSeconds} * interval '1 second'),
            updated_at = ${now.toISOString()}
        from candidate
        where j.id = candidate.id
        returning
          j.id::text,
          j.type,
          j.payload_ciphertext,
          j.nonce,
          j.tag,
          j.key_version,
          j.attempts,
          j.max_attempts
      `;

      if (job === undefined) {
        return undefined;
      }
      return {
        attempts: job.attempts,
        id: job.id,
        keyVersion: job.key_version,
        maxAttempts: job.max_attempts,
        nonce: job.nonce,
        payloadCiphertext: job.payload_ciphertext,
        tag: job.tag,
        type: job.type,
      };
    });
  }

  async complete(jobId: string, workerId: string, now: Date): Promise<boolean> {
    const rows = await this.resource.sql<{ id: string }[]>`
      update app.jobs
      set status = 'succeeded',
          completed_at = ${now.toISOString()},
          locked_by = null,
          lease_expires_at = null,
          last_error = null,
          updated_at = ${now.toISOString()}
      where id = ${jobId}
        and status = 'running'
        and locked_by = ${workerId}
      returning id::text
    `;
    return rows.length === 1;
  }

  async fail(
    job: ClaimedJob,
    workerId: string,
    now: Date,
    retryDelaySeconds: number,
    safeError: string,
  ): Promise<JobFailureResult> {
    const terminal = job.attempts >= job.maxAttempts;
    const rows = await this.resource.sql<{ status: "dead" | "pending" }[]>`
      update app.jobs
      set status = ${terminal ? "dead" : "pending"}::app.job_status,
          available_at =
            ${now.toISOString()}::timestamptz +
            (${terminal ? 0 : retryDelaySeconds} * interval '1 second'),
          completed_at = ${terminal ? now.toISOString() : null},
          locked_by = null,
          lease_expires_at = null,
          last_error = ${safeError},
          updated_at = ${now.toISOString()}
      where id = ${job.id}
        and status = 'running'
        and locked_by = ${workerId}
      returning status
    `;
    if (rows.length === 0) {
      return "lease_lost";
    }
    return terminal ? "dead" : "retry_scheduled";
  }
}
