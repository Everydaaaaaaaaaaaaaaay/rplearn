import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { RuntimeConfig } from "../../src/config/env.js";
import { integrationConfig as loadConfig } from "../helpers/integration.js";
import { runMigrations } from "../../src/db/migrate.js";
import {
  createRuntimeDependencies,
  type RuntimeDependencies,
} from "../../src/infrastructure/runtime-dependencies.js";
import type { AuthNotifier } from "../../src/modules/auth/notifier.js";
import { createJobPayloadCipher } from "../../src/modules/jobs/crypto.js";
import { JobRepository } from "../../src/modules/jobs/repository.js";
import { insertPreparedJob } from "../../src/modules/jobs/transactional-enqueue.js";
import { AUTH_EMAIL_VERIFICATION_JOB } from "../../src/modules/jobs/types.js";
import { JobWorker } from "../../src/modules/jobs/worker.js";
import { newEntityId } from "../../src/shared/id.js";

const runIntegrationTests = process.env.RUN_INTEGRATION_TESTS === "true";

const silentLogger = {
  error: () => undefined,
  info: () => undefined,
  warn: () => undefined,
};

describe.runIf(runIntegrationTests)("durable background jobs", () => {
  let config: RuntimeConfig;
  let dependencies: RuntimeDependencies;
  const jobIds: string[] = [];

  beforeAll(async () => {
    config = loadConfig({
      JOB_RETRY_BASE_SECONDS: "1",
      NODE_ENV: "test",
    });
    dependencies = createRuntimeDependencies(config);
    await runMigrations(dependencies.database);
    await dependencies.start();
  });

  afterAll(async () => {
    if (jobIds.length > 0) {
      await dependencies.database.sql`
        delete from app.jobs
        where id in ${dependencies.database.sql(jobIds)}
      `;
    }
    await dependencies.close();
  });

  async function enqueue(maxAttempts: number): Promise<string> {
    const job = createJobPayloadCipher(config).prepare(
      AUTH_EMAIL_VERIFICATION_JOB,
      {
        email: "jobs@example.com",
        token: "t".repeat(64),
      },
      {
        maxAttempts,
        uniqueKey: `job-test:${newEntityId()}`,
      },
    );
    await dependencies.database.sql.begin((sql) => insertPreparedJob(sql, job));
    jobIds.push(job.id);
    return job.id;
  }

  function worker(workerId: string, notifier: AuthNotifier): JobWorker {
    return new JobWorker({
      cipher: createJobPayloadCipher(config),
      config,
      logger: silentLogger,
      notifier,
      repository: new JobRepository(dependencies.database),
      workerId,
    });
  }

  it("retries transient failures and moves exhausted jobs to dead letter", async () => {
    const jobId = await enqueue(2);
    const failingNotifier: AuthNotifier = {
      sendEmailVerification: () => Promise.reject(new Error("private details")),
      sendPasswordReset: () => Promise.reject(new Error("private details")),
    };
    const subject = worker("failure-worker", failingNotifier);

    expect(await subject.runOnce()).toBe("retry_scheduled");
    expect(await subject.runOnce(new Date(Date.now() + 10_000))).toBe("dead");

    const [job] = await dependencies.database.sql<
      {
        attempts: number;
        last_error: string;
        status: string;
      }[]
    >`
      select attempts, last_error, status
      from app.jobs
      where id = ${jobId}
    `;
    expect(job).toEqual({
      attempts: 2,
      last_error: "Error",
      status: "dead",
    });
  });

  it("uses skip-locked leasing so concurrent workers deliver once", async () => {
    const jobId = await enqueue(3);
    let deliveries = 0;
    const notifier: AuthNotifier = {
      sendEmailVerification: async () => {
        deliveries += 1;
        await Promise.resolve();
      },
      sendPasswordReset: () => Promise.resolve(),
    };

    const results = await Promise.all([
      worker("concurrent-a", notifier).runOnce(),
      worker("concurrent-b", notifier).runOnce(),
    ]);
    expect(results.sort()).toEqual(["idle", "succeeded"]);
    expect(deliveries).toBe(1);

    const [job] = await dependencies.database.sql<
      { attempts: number; status: string }[]
    >`
      select attempts, status
      from app.jobs
      where id = ${jobId}
    `;
    expect(job).toEqual({ attempts: 1, status: "succeeded" });
  });
});
