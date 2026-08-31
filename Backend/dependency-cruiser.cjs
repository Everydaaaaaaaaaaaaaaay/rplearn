const { readdirSync } = require("node:fs");
const { join } = require("node:path");

const modulesDirectory = join(__dirname, "src", "modules");
const moduleNames = readdirSync(modulesDirectory, { withFileTypes: true })
  .filter((entry) => entry.isDirectory())
  .map((entry) => entry.name)
  .sort();

const crossModuleInternalRules = moduleNames.flatMap((moduleName) =>
  ["repository", "schema"].map((internalName) => ({
    name: `no-cross-module-${moduleName}-${internalName}`,
    comment: `Only the ${moduleName} module may import its ${internalName}.ts implementation.`,
    severity: "error",
    from: {
      path: "^src/modules/",
      pathNot: `^src/modules/${moduleName}/`,
    },
    to: {
      path: `^src/modules/${moduleName}/${internalName}\\.ts$`,
    },
  })),
);

module.exports = {
  forbidden: [
    {
      name: "no-circular",
      comment: "Break dependency cycles with a neutral contract or composition root.",
      severity: "error",
      from: {},
      to: { circular: true },
    },
    {
      name: "neutral-layers-do-not-import-modules",
      comment: "Shared infrastructure stays independent of business modules.",
      severity: "error",
      from: { path: "^src/(?:config|db|infrastructure|shared)/" },
      to: { path: "^src/modules/" },
    },
    ...crossModuleInternalRules,
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    tsConfig: { fileName: "tsconfig.json" },
  },
};
