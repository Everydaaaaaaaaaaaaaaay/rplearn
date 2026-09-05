#!/usr/bin/env node
// Audit and preview assets without modifying image pixels. Acceptance is explicit and hash-bound.
import {
  readFileSync,
  writeFileSync,
  existsSync,
  mkdirSync,
  copyFileSync,
} from "node:fs";
import { resolve, dirname, relative } from "node:path";
import { createHash } from "node:crypto";
import { readPng } from "./artasset.mjs";
const root = resolve(import.meta.dirname, "../..");
const folder = resolve(root, "Assets/NPC/Library/v3");
const manifest = JSON.parse(readFileSync(resolve(folder, "catalog.json")));
const themesList = ["blue", "red", "yellow", "violet", "jade"];
if (
  ![100, 200].includes(manifest.milestone) ||
  !Array.isArray(manifest.entries)
)
  throw Error("Invalid catalog structure or milestone");
const keys = new Set(),
  ids = new Set(),
  identities = new Set();
for (const e of manifest.entries) {
  if (
    !e.key ||
    !e.id ||
    !["planned", "generated", "accepted", "rejected", "removed"].includes(
      e.status,
    )
  )
    throw Error("Invalid entry identity/status");
  if (keys.has(e.key) || ids.has(e.id))
    throw Error("Duplicate canonical key or ID");
  keys.add(e.key);
  ids.add(e.id);
  const inside = relative(folder, resolve(folder, e.image));
  if (inside.startsWith("..") || inside.startsWith("/"))
    throw Error("Image outside catalog directory");
  if (!themesList.includes((e.observed ?? e.target)?.theme))
    throw Error("Invalid theme for " + e.key);
  if (!["rejected", "removed"].includes(e.status)) {
    if (!e.identityGroup || identities.has(e.identityGroup))
      throw Error("Duplicate or missing active identity group");
    identities.add(e.identityGroup);
  }
}

const entries = manifest.entries.filter(
  (e) => !["rejected", "removed"].includes(e.status),
);
const command = process.argv[2] ?? "audit";
const output = process.argv[3];
function inspect(e) {
  const path = resolve(folder, e.image);
  if (!existsSync(path))
    return { key: e.key, present: false, status: "missing" };
  try {
    const bytes = readFileSync(path);
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    const png = readPng(path);
    let opaque = true;
    for (let i = 3; i < png.data.length; i += 4)
      if (png.data[i] !== 255) {
        opaque = false;
        break;
      }
    const corners = [
      [0.02, 0.02],
      [0.98, 0.02],
      [0.02, 0.2],
      [0.98, 0.2],
    ].map(([x, y]) => {
      const i =
        (Math.floor(y * png.height) * png.width + Math.floor(x * png.width)) *
        4;
      return [...png.data.subarray(i, i + 4)];
    });
    const backgroundDark = corners.some(
      (c) => Math.max(...c.slice(0, 3)) < 110,
    );
    const review = e.review;
    const accepted =
      review?.status === "accepted" &&
      review.sha256 === sha256 &&
      review.circlePass === true &&
      review.backgroundPass === true &&
      e.observed &&
      review.reviewer &&
      e.status === "accepted";
    return {
      key: e.key,
      present: true,
      sha256,
      width: png.width,
      height: png.height,
      opaque,
      corners,
      backgroundDark,
      status: accepted
        ? "accepted"
        : review?.sha256 === sha256 && review.status !== "accepted"
          ? review.status
          : "pending-review",
      review: review ?? null,
    };
  } catch (error) {
    return {
      key: e.key,
      present: true,
      status: "invalid",
      error: String(error),
    };
  }
}
const assets = entries.map(inspect);
const hashes = new Map();
const duplicates = [];
for (const a of assets.filter((a) => a.sha256)) {
  if (hashes.has(a.sha256)) duplicates.push([hashes.get(a.sha256), a.key]);
  else hashes.set(a.sha256, a.key);
}
const themes = Object.fromEntries(
  themesList.map((theme) => [
    theme,
    {
      target: manifest.milestone / 5,
      present: entries.filter(
        (e) =>
          (e.observed ?? e.target).theme === theme &&
          assets.find((a) => a.key === e.key)?.present,
      ).length,
      accepted: entries.filter(
        (e) =>
          e.observed?.theme === theme &&
          assets.find((a) => a.key === e.key)?.status === "accepted",
      ).length,
    },
  ]),
);
const report = {
  createdAt: new Date().toISOString(),
  planned: assets.length,
  present: assets.filter((a) => a.present).length,
  accepted: assets.filter((a) => a.status === "accepted").length,
  duplicates,
  themes,
  assets,
  limitations: [
    "Pixel checks do not verify facial identity, age, anatomy or artistic quality.",
    "Targets are not observed features. Only explicit SHA-bound reviews can release an asset.",
  ],
};
if (command === "audit") {
  if (output) {
    mkdirSync(dirname(resolve(output)), { recursive: true });
    writeFileSync(output, JSON.stringify(report, null, 2) + "\n");
  }
  console.log(
    JSON.stringify({
      planned: report.planned,
      present: report.present,
      accepted: report.accepted,
      duplicates,
      themes,
      output,
    }),
  );
} else if (command === "export") {
  const base = process.argv[4];
  if (!output || !base || new URL(base).protocol !== "https:")
    throw Error("Usage: export output.json https://cdn/base/");
  if (
    entries.length !== manifest.milestone ||
    report.accepted !== manifest.milestone ||
    duplicates.length
  )
    throw Error("Release blocked: missing, unreviewed or duplicate assets.");
  for (const [theme, quota] of Object.entries(themes))
    if (quota.accepted !== quota.target)
      throw Error(`Theme quota incomplete: ${theme}`);
  const avatars = entries.map((e) => {
    const a = assets.find((a) => a.key === e.key);
    const o = e.observed;
    if (
      !a.opaque ||
      a.width !== a.height ||
      !o.appearance ||
      !Number.isInteger(o.ageMin) ||
      !Number.isInteger(o.ageMax) ||
      o.ageMin < 14 ||
      o.ageMax > 85 ||
      o.ageMin > o.ageMax ||
      !["male", "female", "other"].includes(o.gender) ||
      !Array.isArray(o.tags) ||
      new Set(o.tags).size !== o.tags.length
    )
      throw Error(`Invalid reviewed profile: ${e.key}`);
    return {
      id: e.id,
      url: new URL(
        `${e.key}-${a.sha256.slice(0, 16)}.png`,
        base.endsWith("/") ? base : base + "/",
      ).href,
      tags: o.tags,
      enabled: true,
      profile: {
        ageMin: o.ageMin,
        ageMax: o.ageMax,
        gender: o.gender,
        appearance: o.appearance,
        styleVersion: manifest.styleVersion,
        sha256: a.sha256,
      },
    };
  });
  mkdirSync(dirname(resolve(output)), { recursive: true });
  const releaseDir = resolve(dirname(output), "images");
  mkdirSync(releaseDir, { recursive: true });
  for (const e of entries) {
    const a = assets.find((a) => a.key === e.key);
    copyFileSync(
      resolve(folder, e.image),
      resolve(releaseDir, `${e.key}-${a.sha256.slice(0, 16)}.png`),
    );
  }
  writeFileSync(
    output,
    JSON.stringify({ version: 2, avatars }, null, 2) + "\n",
  );
  console.log(JSON.stringify({ exported: avatars.length, output }));
} else if (command === "gallery") {
  const dest = resolve(output ?? resolve(folder, "review.html"));
  const esc = (s) =>
    String(s)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;");
  const present = entries.filter((e) => existsSync(resolve(folder, e.image)));
  // Alternate themes so the initial viewport also reflects the balanced library.
  const groups = themesList.map((theme) =>
    present.filter((e) => (e.observed ?? e.target).theme === theme).reverse(),
  );
  const presentEntries = Array.from(
    { length: Math.max(...groups.map((group) => group.length)) },
    (_, index) => groups.flatMap((group) => group[index] ?? []),
  ).flat();
  const html = `<!doctype html><html lang="zh"><meta charset="utf-8"><title>NPC 圆形头像检查</title><style>body{font:15px system-ui;margin:32px;background:#f2f3f6;color:#172030}header{position:sticky;top:0;background:#f2f3f6ee;padding:12px;z-index:1}button,select{font:inherit;padding:8px;margin:4px}main{display:grid;grid-template-columns:repeat(auto-fill,minmax(190px,1fr));gap:24px}figure{margin:0;background:white;border-radius:12px;padding:16px;text-align:center}img{width:160px;height:160px;object-fit:cover;border-radius:50%}.small{width:64px;height:64px;margin:12px}.gray img{filter:grayscale(1)}.square img{border-radius:0}figcaption{font-size:12px;line-height:1.7;overflow-wrap:anywhere}p{max-width:85ch}summary{cursor:pointer}</style><header><b>NPC · 圆形裁切与同质化检查</b><p>图片显示为实际 CSS 圆形遮罩；并排比较 160 px 与 64 px。每张可展开实际画像与验收记录；创作简报单独保留。镜像版本属于同一人物，不能重复计数。</p><button onclick="document.body.classList.toggle('gray')">灰度比较</button><button onclick="document.body.classList.toggle('square')">圆形 / 原图</button><select onchange="document.querySelectorAll('figure').forEach(e=>e.hidden=this.value&&e.dataset.theme!==this.value)"><option value="">全部色系</option>${themesList.map((t) => `<option>${t}</option>`).join("")}</select><span>${report.present} / ${report.planned} 张发布候选已生成；${report.accepted} 张已验收</span></header><main>${presentEntries
    .map((e) => {
      const src = esc(relative(dirname(dest), resolve(folder, e.image)));
      const a = assets.find((a) => a.key === e.key);
      return `<figure data-theme="${esc((e.observed ?? e.target).theme)}"><a href="${src}" target="_blank"><img src="${src}" loading="lazy" alt="${esc(e.key)}"></a><br><img class="small" src="${src}" loading="lazy" alt="64 px"><figcaption><b>${esc(e.key)}</b> · ${esc(a?.status ?? "experiment")}<details><summary>实际画像与验收记录</summary><p>${esc(e.observed?.appearance ?? "尚未复核")}</p><p>${esc(JSON.stringify(e.observed ?? {}))}</p><p>${esc(e.review?.notes ?? "")}</p></details><details><summary>创作简报</summary>${esc(JSON.stringify(e.target))}</details></figcaption></figure>`;
    })
    .join("")}</main></html>`;
  writeFileSync(dest, html);
  console.log(JSON.stringify({ gallery: dest, shown: presentEntries.length }));
} else throw Error("Expected audit, gallery or export");
