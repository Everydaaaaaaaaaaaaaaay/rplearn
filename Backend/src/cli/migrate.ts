import "dotenv/config";
import { loadDatabaseConnectionConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { environmentForMigrations, runMigrations } from "../db/migrate.js";

const config = loadDatabaseConnectionConfig(environmentForMigrations(process.env));
const database = createDatabase(config);

try {
  await runMigrations(database);
  process.stdout.write("Database migrations applied successfully.\n");
} finally {
  await database.close();
}
