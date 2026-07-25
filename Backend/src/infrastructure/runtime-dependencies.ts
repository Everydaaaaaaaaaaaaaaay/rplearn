import type { ReadinessCheck } from "../app/readiness.js";
import type { RuntimeConfig } from "../config/env.js";
import { createDatabase, type DatabaseResource } from "../db/client.js";
import { assertMigrationsCurrent } from "../db/migrate.js";
import { createRedisResource, type RedisResource } from "./redis/client.js";

export type RuntimeDependencies = Readonly<{
  close: () => Promise<void>;
  database: DatabaseResource;
  onRedisError: (listener: (error: Error) => void) => void;
  readinessChecks: readonly ReadinessCheck[];
  redis: RedisResource;
  start: () => Promise<void>;
}>;

export function createRuntimeDependencies(config: RuntimeConfig): RuntimeDependencies {
  const database = createDatabase(config);
  const redis = createRedisResource(config);
  const readinessChecks: readonly ReadinessCheck[] = [
    {
      check: async () => {
        await database.ping();
        await assertMigrationsCurrent(database);
      },
      name: "postgresql",
    },
    {
      check: redis.ping,
      name: "redis",
    },
  ];

  return {
    close: async () => {
      await Promise.allSettled([redis.close(), database.close()]);
    },
    database,
    onRedisError: redis.onError,
    readinessChecks,
    redis,
    start: redis.connect,
  };
}
