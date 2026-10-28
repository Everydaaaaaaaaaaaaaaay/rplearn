import { readFileSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { z } from "zod";
import {
  contentHash,
  questionAudios,
  questionImageIds,
  unitSchema,
  type LearningUnit,
} from "./content.js";
import { gradeAnswer } from "./grading.js";
import { questionForGrading } from "./grading-revisions.js";
import { learningImageSchema, verifyLearningImage } from "./images.js";
import {
  learningAudioSchema,
  verifyLearningAudioFile,
  type DeferredLearningAudio,
} from "./audio.js";

export const expansionRun = "2026-10-24";
export const expansionRuns = [expansionRun, "2026-10-28"] as const;
const runSchema = z.enum(expansionRuns);
export function expansionNamespace(run: string = expansionRun) {
  return `expansion.${runSchema.parse(run).replaceAll("-", "")}.`;
}
const component = z.strictObject({
  id: z.string(),
  family: z.enum([
    "reading_choice",
    "choice_cloze",
    "shared_insertion",
    "passage_form",
  ]),
  questionIds: z.array(z.string()).min(3),
  sourceNumbers: z.array(z.number().int()),
  sourceUnitId: z.string().optional(),
  sourceContentHash: z.string().optional(),
});
const entry = z.strictObject({
  unit: unitSchema,
  contentHash: z.string().regex(/^[a-f0-9]{64}$/),
  reviewNotes: z.string().min(30),
  components: z.array(component).optional(),
  revises: z
    .strictObject({
      version: z.number().int().min(1).max(2147483647),
      contentHash: z.string().regex(/^[a-f0-9]{64}$/),
      sourceSHA256: z.string().regex(/^[a-f0-9]{64}$/),
    })
    .optional(),
});
const manifestSchema = z.strictObject({
  version: z.literal(1),
  run: runSchema,
  batch: z.string().regex(/^b[0-9]{3}$/),
  createdAt: z.string(),
  entries: z.array(entry).min(1).max(30),
  imageAssets: z.array(learningImageSchema).optional(),
  audioAssets: z.array(learningAudioSchema).optional(),
  newAudioAssetIds: z.array(z.string().regex(/^audio\.[a-f0-9]{64}$/)).optional(),
  sourceSHA256: z
    .string()
    .regex(/^[a-f0-9]{64}$/)
    .optional(),
  reviewSHA256: z
    .string()
    .regex(/^[a-f0-9]{64}$/)
    .optional(),
  reviewKind: z.literal("author-self-review").optional(),
  reviewer: z.string().min(1).optional(),
});
const indexSchema = z.strictObject({
  version: z.literal(1),
  run: runSchema,
  batches: z.array(z.string().regex(/^b[0-9]{3}$/)).max(500),
  gaokaoBatches: z.array(z.string().regex(/^b[0-9]{3}$/)).optional(),
});

/** The authoring gate and runtime must validate the same complete release envelope. */
export function parseExpansionManifest(value: unknown) {
  return manifestSchema.parse(value);
}

/** New content is separate from the frozen old catalogs and has a withdrawable run identity. */
export function loadExpansionCatalog(
  batch?: string,
  highSchoolOnly = false,
  run: string = expansionRun,
) {
  const namespace = expansionNamespace(run);
  const directory = new URL(
    `../../../config/learning/expansions/${run}/`,
    import.meta.url,
  );
  const index = indexSchema.parse(
    JSON.parse(readFileSync(new URL("index.json", directory), "utf8")),
  );
  if (
    index.run !== run ||
    new Set(index.batches).size !== index.batches.length ||
    (index.gaokaoBatches ?? []).some((id) => !index.batches.includes(id)) ||
    (batch && !index.batches.includes(batch))
  )
    throw new Error("Unknown or duplicate expansion batch");
  // Revision predecessors may be in an unselected batch; verify the indexed chain.
  const selectedBatch = (id: string) =>
    (!batch || id === batch) && (!highSchoolOnly || index.gaokaoBatches?.includes(id));
  const allManifests = index.batches
    .filter((id) => run === "2026-10-28" || selectedBatch(id))
    .map((id) => {
      const manifest = parseExpansionManifest(
        JSON.parse(readFileSync(new URL(`${id}.json`, directory), "utf8")),
      );
      if (manifest.batch !== id || manifest.run !== run)
        throw new Error("Expansion batch identity mismatch");
      if (
        run === "2026-10-28" &&
        (!manifest.sourceSHA256 ||
          !manifest.reviewSHA256 ||
          !manifest.reviewKind ||
          !manifest.reviewer)
      )
        throw new Error("Expansion author review binding missing");
      const newAudio = manifest.newAudioAssetIds ?? [];
      if (
        new Set(newAudio).size !== newAudio.length ||
        newAudio.some((id) => !manifest.audioAssets?.some((a) => a.id === id)) ||
        (run !== "2026-10-28" && newAudio.length > 0)
      )
        throw new Error("Expansion selected new audio identity mismatch");
      return manifest;
    });
  const manifests = allManifests.filter((m) => selectedBatch(m.batch));
  const allEntries = allManifests.flatMap((manifest) =>
    manifest.entries.map((entry) => ({ entry, manifest })),
  );
  const identity = (u: LearningUnit) => `${u.id}:${String(u.version)}`;
  const byVersion = new Map(allEntries.map((row) => [identity(row.entry.unit), row]));
  if (
    byVersion.size !== allEntries.length ||
    allManifests.some(
      (m) => new Set(m.entries.map((e) => e.unit.id)).size !== m.entries.length,
    )
  )
    throw new Error("Duplicate expansion unit version");
  for (const { entry: e, manifest } of allEntries) {
    const u = e.unit;
    if (
      !u.id.startsWith(namespace) ||
      u.version > 2147483647 ||
      (run !== "2026-10-28" && (u.version !== 1 || e.revises !== undefined)) ||
      !u.originalGroup ||
      u.roleKey !== "companion" ||
      u.authorship.kind !== "authored" ||
      contentHash(u) !== e.contentHash ||
      !u.originalGroup.sourceNotice.includes(run)
    )
      throw new Error(`Expansion identity/digest mismatch: ${u.id}`);
    if (u.version === 1 && e.revises !== undefined)
      throw new Error(`Initial expansion version cannot revise another: ${u.id}`);
    if (u.version > 1) {
      const binding = e.revises;
      const previous = binding
        ? byVersion.get(`${u.id}:${String(binding.version)}`)
        : undefined;
      if (
        binding?.version !== u.version - 1 ||
        previous?.entry.contentHash !== binding.contentHash ||
        previous.manifest.sourceSHA256 !== binding.sourceSHA256 ||
        previous.entry.unit.level !== u.level ||
        previous.entry.unit.roleKey !== u.roleKey
      )
        throw new Error(
          `Expansion revision previous unit/source binding mismatch: ${u.id}`,
        );
    }
    for (const frozen of u.questions) {
      // Frozen hashes stay authoritative; probes use only explicitly reviewed effective forms.
      const q = questionForGrading(frozen);
      if (!q.material) throw new Error(`Incomplete expansion input: ${u.id}/${q.id}`);
      if (run === "2026-10-28") {
        for (const audio of questionAudios(q))
          if (
            !manifest.audioAssets?.some(
              (a) =>
                a.id === audio.assetId &&
                a.transcript === audio.text &&
                a.voice === audio.voice,
            )
          )
            throw new Error(`Expansion audio binding mismatch: ${u.id}/${q.id}`);
        for (const imageId of questionImageIds(q))
          if (!manifest.imageAssets?.some((a) => a.id === imageId))
            throw new Error(`Expansion image binding mismatch: ${u.id}/${q.id}`);
      }
      if (q.type === "choice") {
        if (/[一-鿿]/u.test(q.prompt + q.options.map((o) => o.text).join("")))
          throw new Error(`Expansion choice language mismatch: ${u.id}/${q.id}`);
        for (const o of q.options)
          if (
            (gradeAnswer(q, { kind: "choice", optionId: o.id }).outcome ===
              "correct") !==
            (o.id === q.answer)
          )
            throw new Error("Expansion choice grading mismatch");
      } else if (q.type === "completion") {
        if (!q.marking) throw new Error("Expansion completion needs bounded marking");
        for (const text of q.acceptedAnswers)
          if (gradeAnswer(q, { kind: "text", text }).outcome !== "correct")
            throw new Error("Expansion accepted answer mismatch");
        for (const text of q.marking.rejectedAnswers)
          if (gradeAnswer(q, { kind: "text", text }).outcome !== "incorrect")
            throw new Error("Expansion rejected answer mismatch");
      } else if (q.type !== "listeningChoice")
        throw new Error("Expansion interaction not supported");
    }
    if (
      /^senior[123]$/.test(u.level) &&
      (!e.components || !u.title.startsWith("高考题型原创"))
    )
      throw new Error("Senior expansion needs complete Gaokao components");
  }
  const latest = new Map<string, z.infer<typeof entry>>();
  for (const e of manifests.flatMap((m) => m.entries))
    if ((latest.get(e.unit.id)?.unit.version ?? 0) < e.unit.version)
      latest.set(e.unit.id, e);
  const entries = [...latest.values()];
  return {
    manifests,
    entries,
    units: entries.map((e) => e.unit),
    hash: contentHash(manifests),
  };
}

export function expansionGaokaoPractices() {
  return expansionRuns
    .flatMap((run) => loadExpansionCatalog(undefined, true, run).entries)
    .filter((e) => /^senior[123]$/.test(e.unit.level))
    .map((e) => ({
      kind: "authored" as const,
      unit: e.unit,
      contentHash: e.contentHash,
      components: e.components ?? [],
    }));
}

export function isExpansionUnit(unit: LearningUnit) {
  return expansionRuns.some((run) => unit.id.startsWith(expansionNamespace(run)));
}

/** Verify only selected-batch new assets, never the old media corpus. */
export async function loadExpansionImages(batch: string, run: string = expansionRun) {
  const catalog = loadExpansionCatalog(batch, false, run);
  const metadata = catalog.manifests.flatMap((m) => m.imageAssets ?? []);
  return Promise.all(
    metadata.map(async (asset) => {
      const path =
        process.env.NODE_ENV === "production"
          ? `/opt/lingotrip/shared/learning-originals-media/${asset.id}.png`
          : fileURLToPath(
              new URL(
                `../../../config/learning/originals/media/${asset.id}.png`,
                import.meta.url,
              ),
            );
      const bytes = await readFile(path);
      verifyLearningImage(asset, bytes);
      return { metadata: asset, loadBytes: () => Promise.resolve(bytes) };
    }),
  );
}

/** Only selected, explicitly declared clips are checked; publishing reuses archived metadata. */
function expansionAudioPath(id: string) {
  return process.env.NODE_ENV === "production"
    ? `/opt/lingotrip/shared/learning-originals-media/${id}.wav`
    : fileURLToPath(
        new URL(`../../../config/learning/originals/media/${id}.wav`, import.meta.url),
      );
}

export async function verifyExpansionAudio(batch: string, run: string = expansionRun) {
  const catalog = loadExpansionCatalog(batch, false, run);
  for (const asset of catalog.manifests.flatMap((m) => m.audioAssets ?? [])) {
    await verifyLearningAudioFile(asset, expansionAudioPath(asset.id));
  }
}

/** Upload only selected new clips; existing original clips stay in their current archive. */
export async function loadExpansionAudio(
  batch: string,
  run: string = expansionRun,
): Promise<DeferredLearningAudio[]> {
  const catalog = loadExpansionCatalog(batch, false, run);
  const assets = catalog.manifests.flatMap((m) =>
    (m.audioAssets ?? []).filter((a) => m.newAudioAssetIds?.includes(a.id)),
  );
  return Promise.all(
    assets.map(async (metadata) => {
      const filePath = expansionAudioPath(metadata.id);
      await verifyLearningAudioFile(metadata, filePath);
      return { metadata, filePath, loadBytes: () => readFile(filePath) };
    }),
  );
}
