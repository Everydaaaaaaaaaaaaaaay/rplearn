import "dotenv/config";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { environmentForMigrations, runMigrations } from "../db/migrate.js";

const config = loadConfig(environmentForMigrations(process.env));
const database = createDatabase(config);

try {
  await runMigrations(database);
  process.stdout.write("Database migrations applied successfully.\n");
} finally {
  await database.close();
}
