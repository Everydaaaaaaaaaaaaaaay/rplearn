import type { RuntimeConfig } from "../../src/config/env.js";
import type { DatabaseResource } from "../../src/db/client.js";
import type { AuthNotifier } from "../../src/modules/auth/notifier.js";
import { createJobPayloadCipher } from "../../src/modules/jobs/crypto.js";
import { JobRepository } from "../../src/modules/jobs/repository.js";
import { JobWorker } from "../../src/modules/jobs/worker.js";
import { newEntityId } from "../../src/shared/id.js";

const silentLogger = {
  error: () => undefined,
  info: () => undefined,
  warn: () => undefined,
};

export function createTestJobWorker(
  config: RuntimeConfig,
  database: DatabaseResource,
  notifier: AuthNotifier,
  options: Readonly<{
    processAccountPurge?: (
      payload: Readonly<{ requestId: string; userId: string }>,
    ) => Promise<void>;
    processMediaDelete?: (
      payload: Readonly<{ assetId: string; objectKey: string }>,
    ) => Promise<void>;
  }> = {},
): JobWorker {
  return new JobWorker({
    cipher: createJobPayloadCipher(config),
    config,
    logger: silentLogger,
    notifier,
    ...(options.processAccountPurge === undefined
      ? {}
      : { processAccountPurge: options.processAccountPurge }),
    ...(options.processMediaDelete === undefined
      ? {}
      : { processMediaDelete: options.processMediaDelete }),
    repository: new JobRepository(database),
    workerId: `test-worker-${newEntityId()}`,
  });
}
