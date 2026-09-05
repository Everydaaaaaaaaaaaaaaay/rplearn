#!/usr/bin/env node
// Exercise release failures in an isolated copy; never mutate the working catalog.
import assert from "node:assert/strict";
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  copyFileSync,
  symlinkSync,
  rmSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(import.meta.dirname, "../..");
const source = resolve(root, "Assets/NPC/Library/v3");
const catalog = JSON.parse(readFileSync(resolve(source, "catalog.json")));
const fixture = mkdtempSync(resolve(tmpdir(), "npc-release-gates-"));
const results = [];
try {
  const scripts = resolve(fixture, "Tools/ArtPipeline");
  const assets = resolve(fixture, "Assets/NPC/Library/v3");
  mkdirSync(scripts, { recursive: true });
  mkdirSync(assets, { recursive: true });
  for (const file of ["npc-library-audit.mjs", "artasset.mjs"])
    copyFileSync(resolve(import.meta.dirname, file), resolve(scripts, file));
  symlinkSync(resolve(source, "images"), resolve(assets, "images"));
  function check(
    name,
    mutate,
    expected,
    base = "https://example.invalid/npc/",
  ) {
    const changed = structuredClone(catalog);
    mutate(changed);
    writeFileSync(resolve(assets, "catalog.json"), JSON.stringify(changed));
    const result = spawnSync(
      process.execPath,
      [
        resolve(scripts, "npc-library-audit.mjs"),
        "export",
        resolve(fixture, "release/manifest.json"),
        base,
      ],
      { encoding: "utf8" },
    );
    if (expected) {
      assert.notEqual(result.status, 0, name);
      assert.match(result.stderr, expected, name);
    } else {
      assert.equal(result.status, 0, result.stderr);
      const manifest = JSON.parse(
        readFileSync(resolve(fixture, "release/manifest.json")),
      );
      assert.equal(manifest.avatars.length, catalog.milestone);
      assert.equal(manifest.version, 2);
    }
    results.push({ name, passed: true });
  }
  const active = (c) => c.entries.filter((e) => e.status === "accepted");
  check("complete reviewed release", () => {}, null);
  check(
    "duplicate canonical ID",
    (c) => {
      active(c)[1].id = active(c)[0].id;
    },
    /Duplicate canonical/,
  );
  check(
    "duplicate identity group",
    (c) => {
      active(c)[1].identityGroup = active(c)[0].identityGroup;
    },
    /Duplicate or missing active/,
  );
  check(
    "escaping image path",
    (c) => {
      active(c)[0].image = "../../outside.png";
    },
    /Image outside/,
  );
  check(
    "stale SHA review",
    (c) => {
      active(c)[0].review.sha256 = "0".repeat(64);
    },
    /Release blocked/,
  );
  check(
    "missing background review",
    (c) => {
      delete active(c)[0].review.backgroundPass;
    },
    /Release blocked/,
  );
  check(
    "missing image",
    (c) => {
      active(c)[0].image = "images/missing.png";
    },
    /Release blocked/,
  );
  check(
    "duplicate image bytes",
    (c) => {
      const a = active(c);
      a[1].image = a[0].image;
      a[1].review.sha256 = a[0].review.sha256;
    },
    /Release blocked/,
  );
  check(
    "theme imbalance",
    (c) => {
      const a = active(c)[0];
      a.observed.theme = a.observed.theme === "blue" ? "red" : "blue";
    },
    /Theme quota incomplete/,
  );
  check(
    "invalid observed age",
    (c) => {
      active(c)[0].observed.ageMin = 1;
    },
    /Invalid reviewed profile/,
  );
  check(
    "unreviewed candidate",
    (c) => {
      active(c)[0].status = "planned";
    },
    /Release blocked/,
  );
  check(
    "non-HTTPS destination",
    () => {},
    /Usage: export/,
    "http://example.invalid/npc/",
  );
  const report = {
    createdAt: new Date().toISOString(),
    catalogMilestone: catalog.milestone,
    results,
    destination: "isolated temporary fixture; no upload",
  };
  if (process.argv[2])
    writeFileSync(
      resolve(process.argv[2]),
      JSON.stringify(report, null, 2) + "\n",
    );
  console.log(JSON.stringify(report));
} finally {
  rmSync(fixture, { recursive: true, force: true });
}
