import "dotenv/config";
import { defineConfig } from "drizzle-kit";

const developmentDatabaseUrl =
  "postgres://lingotrip:lingotrip_dev@127.0.0.1:54329/lingotrip";

export default defineConfig({
  dbCredentials: {
    url: process.env.DATABASE_URL ?? developmentDatabaseUrl,
  },
  dialect: "postgresql",
  out: "./migrations",
  schema: ["./src/db/*schema.ts", "./src/modules/**/schema.ts"],
  strict: true,
  verbose: true,
});
