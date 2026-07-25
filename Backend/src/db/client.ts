import { drizzle, type PostgresJsDatabase } from "drizzle-orm/postgres-js";
import postgres, { type Sql } from "postgres";
import type { RuntimeConfig } from "../config/env.js";
import * as schema from "./schema.js";

export type Database = PostgresJsDatabase<typeof schema>;

export type DatabaseResource = Readonly<{
  close: () => Promise<void>;
  database: Database;
  ping: () => Promise<void>;
  sql: Sql;
}>;

function millisecondsToSeconds(milliseconds: number): number {
  return Math.max(1, Math.ceil(milliseconds / 1000));
}

export function createDatabase(config: RuntimeConfig): DatabaseResource {
  const sql = postgres(config.databaseUrl, {
    connect_timeout: millisecondsToSeconds(config.databaseConnectTimeoutMs),
    idle_timeout: millisecondsToSeconds(config.databaseIdleTimeoutMs),
    max: config.databaseMaxConnections,
    prepare: false,
  });
  const database = drizzle(sql, { schema });

  return {
    close: async () => {
      await sql.end({
        timeout: millisecondsToSeconds(config.shutdownGraceMs),
      });
    },
    database,
    ping: async () => {
      await sql`select 1`;
    },
    sql,
  };
}
