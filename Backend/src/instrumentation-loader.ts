import { register } from "node:module";

// Node 24.0-24.11 cannot safely use registerHooks() for the nullish CommonJS
// sources required by import-in-the-middle. Keep this compatibility bridge
// until the minimum runtime reaches a release supported by synchronous hooks.
// eslint-disable-next-line @typescript-eslint/no-deprecated
register("@opentelemetry/instrumentation/hook.mjs", import.meta.url);
