#!/usr/bin/env node
// No image-provider calls. Append concrete briefs to the current reviewed catalog.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import {
  faces,
  expressions,
  hairstyles,
  poses,
  cameras,
  outfits,
  counts,
} from "./npc-diversity-vocabulary.mjs";
const folder = resolve(import.meta.dirname, "../../Assets/NPC/Library/v3");
const path = resolve(folder, "catalog.json");
const c = JSON.parse(readFileSync(path));
const style = readFileSync(resolve(folder, "style.txt"), "utf8");
const target = Number(process.argv[2] ?? 100);
if (![100, 200].includes(target)) throw Error("Expected 100 or 200");
const gapPath = process.argv[3];
if (target === 200 && !gapPath)
  throw Error(
    "Expansion past 100 requires an actual saved batch-test gap report",
  );
const gapReport = gapPath ? JSON.parse(readFileSync(gapPath)) : null;
if (
  gapReport &&
  gapReport.catalogSha256 !==
    createHash("sha256").update(readFileSync(path)).digest("hex")
)
  throw Error(
    "Gap report is stale: retest the current catalog before planning",
  );
const gaps = (gapReport?.gaps ?? []).map((g, i) => ({
  ...g,
  index: i,
  assigned: 0,
}));
const batchLimit = target === 200 ? Number(process.argv[4] ?? 20) : Infinity;
if (
  target === 200 &&
  (!gapReport?.catalogSha256 || !gapReport?.stats || !gaps.length)
)
  throw Error("Expected an aggregated real E2E gap report");
if (
  target === 200 &&
  c.entries.filter((e) => e.status === "accepted").length < 100
)
  throw Error(
    "Review and accept 100 images before starting the optimization expansion",
  );
const colors = {
  blue: ["#09B4E8", "#09587D"],
  red: ["#EF3340", "#A71927"],
  yellow: ["#F4D928", "#9C831C"],
  violet: ["#8956DF", "#553291"],
  jade: ["#16B994", "#147D66"],
};
let seed = 9062026 + target + c.entries.length * 103;
function rand() {
  seed |= 0;
  seed = (seed + 0x6d2b79f5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}
const pick = (a) => a[Math.floor(rand() * a.length)];
const allTags = (e) => e.observed ?? e.target;
const quota = Object.fromEntries(
  Object.keys(colors).map((t) => [
    t,
    c.entries.filter(
      (e) =>
        !["rejected", "removed"].includes(e.status) && allTags(e)?.theme === t,
    ).length,
  ]),
);
const bands = [
  [14, 17],
  [18, 24],
  [25, 34],
  [35, 44],
  [45, 54],
  [55, 64],
  [65, 74],
  [75, 85],
];
const contrasts = [
  "wide neck and broad angular shoulders",
  "short full neck and softly rounded broad shoulders",
  "slender neck and narrow shoulders",
  "ordinary neck and average shoulders",
  "short neck and compact sturdy shoulders",
];
let added = 0;
while (
  c.entries.filter((e) => !["rejected", "removed"].includes(e.status)).length <
    target &&
  added < batchLimit
) {
  const next =
    Math.max(
      0,
      ...c.entries
        .filter((e) => e.key.startsWith("npc-v5-"))
        .map((e) => Number(e.key.slice(7))),
    ) + 1;
  const key = `npc-v5-${String(next).padStart(3, "0")}`;
  const theme = Object.keys(colors)
    .filter((t) => quota[t] < target / 5)
    .sort((a, b) => quota[a] - quota[b])[0];
  if (!theme) throw Error("No remaining palette quota");
  const eligibleGaps = gaps.filter(
    (g) =>
      g.count > 0 &&
      (!g.request.requiredTags.some((t) => t.startsWith("theme:")) ||
        g.request.requiredTags.includes(`theme:${theme}`)),
  );
  const weight = (g) =>
    (g.count *
      (g.reason === "coverage_gap" ? 4 : g.reason === "weak_depth" ? 2 : 1)) /
    (1 + g.assigned * 4);
  const gap = eligibleGaps.sort(
    (a, b) => weight(b) - weight(a) || a.index - b.index,
  )[0];
  if (gap) gap.assigned++;
  const requiredTags = gap?.request?.requiredTags ?? [];
  const hardValue = (namespace) =>
    requiredTags.find((t) => t.startsWith(namespace + ":"))?.split(":")[1];
  const body =
    hardValue("body") ??
    ["broad", "full", "slim", "average", "stocky"][added % 5];
  const bodyIndex = ["broad", "full", "slim", "average", "stocky"].indexOf(
    body,
  );
  const facing = hardValue("facing"),
    emotion = hardValue("expression");
  const cameraPool = facing
    ? cameras.filter((c) =>
        facing === "front" ? c.yaw === "front" : c.yaw.includes(facing),
      )
    : cameras;
  const aliases = {
    calm: "warmth",
    neutral: "resolve",
    laugh: "joy",
    smile: "warmth",
    skeptical: "skepticism",
    worried: "concern",
    tired: "fatigue",
    angry: "annoyance",
    sad: "concern",
    curious: "curiosity",
    surprised: "surprise",
    focused: "focus",
  };
  const effectiveEmotion = aliases[emotion] ?? emotion;
  const expressionPool = effectiveEmotion
    ? expressions.filter((e) =>
        e.description.startsWith(effectiveEmotion + ":"),
      )
    : expressions;
  if (!cameraPool.length || !expressionPool.length)
    throw Error(
      "Unsupported hard camera/expression constraint: " +
        JSON.stringify(requiredTags),
    );
  let choice;
  for (let attempt = 0; attempt < 2000; attempt++) {
    choice = {
      face: pick(faces),
      expression: pick(expressionPool.length ? expressionPool : expressions),
      hair: pick(hairstyles),
      pose: pick(poses),
      camera: pick(cameraPool),
      outfit: pick(outfits),
    };
    const signature = Object.values(choice).map((v) => v.id);
    if (
      c.entries.every(
        (e) =>
          !e.target?.signature ||
          signature.filter((v, i) => v !== e.target.signature[i]).length >= 4,
      )
    )
      break;
    if (attempt === 1999) throw Error("No suitably distinct brief found");
  }
  const band = gap?.request?.age
    ? bands.find(([lo, hi]) => gap.request.age >= lo && gap.request.age <= hi)
    : bands[(next + Math.floor(next / 8)) % 8];
  const gender =
    gap?.request?.gender ??
    ["male", "female", "other"][(next + Math.floor(next / 3)) % 3];
  const age = Math.round((band[0] + band[1]) / 2);
  const [main, shadow] = colors[theme];
  const { face, expression, hair, pose, camera, outfit } = choice;
  const cameraProof = camera.yaw.startsWith("profile")
    ? "STRICT TRUE SIDE PROFILE: exactly ONE eye; far eye, eyebrow and cheek hidden. Nose lips and chin are the outside face contour."
    : camera.yaw === "front"
      ? "Strict frontal facial yaw: centered nose, equal eyes and ears. Tilt shoulders for artistry."
      : "";
  const pitchProof =
    camera.pitch === "high-angle"
      ? "Camera visibly above eye level: crown plane visible, eyes look up, chin foreshortened."
      : camera.pitch === "low-angle"
        ? "Camera visibly below eye level: underside of chin visible, crown hidden."
        : "";
  const direction = camera.yaw.includes("right")
    ? "nose points at RIGHT IMAGE EDGE, visible ear on IMAGE LEFT"
    : camera.yaw.includes("left")
      ? "nose points at LEFT IMAGE EDGE, visible ear on IMAGE RIGHT"
      : "both eyes similar size, nose centered, near symmetrical frontal head";
  const design = {
    ageMin: band[0],
    ageMax: band[1],
    age,
    gender,
    theme,
    body,
    face: face.id,
    faceDescription: face.description,
    expression: expression.id,
    expressionDescription: expression.description,
    hair: hair.id,
    hairDescription: hair.description,
    pose: pose.id,
    poseDescription: pose.description,
    camera: camera.id,
    outfit: outfit.id,
    outfitDescription: outfit.description,
    signature: Object.values(choice).map((v) => v.id),
    background: [
      "large sweeping lower arc",
      "broad diagonal side cut",
      "wide deeper color band along one edge",
      "offset circular arc behind shoulder",
      "single deeper sloped lower field",
    ][added % 5],
  };
  const prompt = `${style}\nINDIVIDUAL: ${age}-year-old ${gender === "female" ? "woman" : gender === "male" ? "man" : "androgynously presented person"}, ${contrasts[Math.max(0, bodyIndex)]}. FACIAL GEOMETRY: ${face.description}. Keep facial proportions distinctly recognizable through silhouette and few marks. ${age >= 60 ? "Clearly older adult: jowls, eyelid weight, cheek structure and posture; just a few purposeful age lines, no youthful model face." : ""}\nHAIR SILHOUETTE: ${hair.description}. Do not add white forelock except an entirely white hairstyle if explicitly requested. ${added % 7 === 0 ? "Small round glasses." : added % 11 === 0 ? "Narrow rectangular glasses." : "No glasses."}\nFACIAL EXPRESSION: ${expression.description}. Mouth/eyes/brows visibly differ from a generic polite smile.\nGESTURE: ${pose.description}. CAMERA: ${camera.description}; ${direction}. ${cameraProof} ${pitchProof} The camera orientation takes priority if a gesture description conflicts. Adapt pose into head-and-upper-chest crop, never full figure.\nWARDROBE: ${outfit.description}. One broad readable garment silhouette, no little details.\nPALETTE: main ${main}; deeper ${shadow}; near-black #09121B; neutral white #FAFBFC. No colors outside this family. BACKGROUND: bright main ${main} plus ${design.background} in deeper ${shadow}, approximately 20% of background, no black background and not completely flat single-value background.\nMake this one ORIGINAL standalone character distinct from previously generated portraits in face, expression, silhouette and clothing. Do not copy an existing character or use a stock handsome anime face. One clean finished FULL-BLEED SQUARE portrait: theme field reaches all four corners, NEVER a baked circular mask. All facial landmarks and entire hair/headwear fit inside central x=20–80%, y=14–76% region. Render a modest head size to fit. No routine scarf unless specifically requested.`;
  const h = createHash("sha256").update(`lingotrip:${key}`).digest("hex");
  const id = `${h.slice(0, 8)}-${h.slice(8, 12)}-4${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`;
  c.entries.push({
    id,
    key,
    identityGroup: key,
    batch: target === 100 ? "foundation-after-prune" : "gap-optimization",
    image: `images/${key}.png`,
    status: "planned",
    target: design,
    prompt,
    observed: null,
    review: null,
    gapSource: gap
      ? {
          report: gapPath,
          request: gap.request,
          reason: gap.reason,
          count: gap.count,
        }
      : null,
  });
  quota[theme]++;
  added++;
}
c.milestone = target;
c.vocabularyCounts = counts;
writeFileSync(path, JSON.stringify(c, null, 2) + "\n");
console.log(JSON.stringify({ added, total: c.entries.length, quota }));
