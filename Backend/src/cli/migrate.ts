import "dotenv/config";
import { loadDatabaseConnectionConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";
import { environmentForMigrations, runMigrations } from "../db/migrate.js";
import { publishBundledActivityWorld } from "../modules/npc/bundled-activity-world.js";

const config = loadDatabaseConnectionConfig(environmentForMigrations(process.env));
const database = createDatabase(config);

try {
  await runMigrations(database);
  const activityWorld = await publishBundledActivityWorld(database);
  if (activityWorld) process.stdout.write(JSON.stringify(activityWorld) + "\n");
  process.stdout.write("Database migrations applied successfully.\n");
} finally {
  await database.close();
}
