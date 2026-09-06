import { loadConfig } from "../../src/config/env.js";

/** Integration suites mutate data. Never silently fall back to a developer database. */
export function integrationConfig(overrides: NodeJS.ProcessEnv = {}) {
  const environment = {
    DATABASE_URL: process.env.DATABASE_URL,
    REDIS_URL: process.env.REDIS_URL,
    ...overrides,
    NODE_ENV: "test",
  };
  for (const key of ["DATABASE_URL", "REDIS_URL"] as const) {
    const value = environment[key];
    if (!value)
      throw new Error(`${key} must explicitly target an isolated test service`);
    const url = new URL(value);
    if (!["127.0.0.1", "localhost", "[::1]"].includes(url.hostname)) {
      throw new Error(`${key} must target a local isolated test service`);
    }
    if (key === "DATABASE_URL" && !/^\/lingotrip_test_[a-z0-9_]+$/.test(url.pathname)) {
      throw new Error("Integration database name must start with lingotrip_test_");
    }
  }
  return loadConfig(environment);
}
