import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { avatarManifestSchema, type AvatarManifest } from "../avatar-catalog.js";
import { hashDistance } from "./images.js";
import type { Candidate, CollectionState, Review } from "./types.js";

export type PreparedCollection = Readonly<{
  manifest: AvatarManifest;
  files: readonly Readonly<{
    key: string;
    path: string;
    byteLength: number;
    sha256: string;
    contentType: string;
  }>[];
}>;
export async function prepareReviewedCollection(
  directory: string,
  state: CollectionState,
  review: Review,
  publicBaseURL: string,
): Promise<PreparedCollection> {
  const base = new URL(
    publicBaseURL.endsWith("/") ? publicBaseURL : publicBaseURL + "/",
  );
  if (
    base.protocol !== "https:" ||
    base.search ||
    base.hash ||
    base.username ||
    base.password
  ) {
    throw new Error(
      "Public base URL must be HTTPS without credentials, query or fragment",
    );
  }
  const approved: {
    candidate: Candidate;
    decision: Extract<Review["decisions"][number], { decision: "approve" }>;
  }[] = [];
  for (const decision of review.decisions) {
    const candidate = state.candidates[decision.candidateId];
    if (!candidate)
      throw new Error(`Unknown review candidate: ${decision.candidateId}`);
    if (decision.decision === "reject") continue;
    if (candidate.file?.sha256 !== decision.sha256)
      throw new Error(`Review does not match downloaded bytes: ${candidate.id}`);
    if (
      candidate.source.provider === "openverse" &&
      (decision.originalSourceCheck?.pageUrl !== candidate.source.recordURL ||
        decision.originalSourceCheck.licenseUrl !== candidate.source.licenseURL)
    ) {
      throw new Error(
        `Openverse approval requires original creator-page verification: ${candidate.id}`,
      );
    }
    if (
      candidate.source.rightsScreen !== "eligible-for-review" ||
      decision.metadata.source.kind !== "licensed" ||
      decision.metadata.source.license !== candidate.source.licenseLabel ||
      (candidate.source.licenseLabel.startsWith("CC BY") &&
        !decision.metadata.source.attributionRequired)
    ) {
      throw new Error(
        `Review must preserve screened license obligations: ${candidate.id}`,
      );
    }
    if (
      decision.metadata.source.pageUrl !== candidate.source.recordURL ||
      decision.metadata.source.licenseUrl !== candidate.source.licenseURL
    ) {
      throw new Error(
        `Review changed the source or license: ${candidate.id}. Record any newly obtained rights separately before approval.`,
      );
    }
    approved.push({ candidate, decision });
  }
  for (let i = 0; i < approved.length; i += 1) {
    for (let j = i + 1; j < approved.length; j += 1) {
      const left = approved[i];
      const right = approved[j];
      if (!left?.candidate.file || !right?.candidate.file) continue;
      const sameFamily = left.decision.familyId === right.decision.familyId;
      const identical = left.candidate.file.sha256 === right.candidate.file.sha256;
      if (identical && !sameFamily)
        throw new Error("Identical bytes must share one avatar family");
      if (
        !sameFamily &&
        hashDistance(left.candidate.file.dhash, right.candidate.file.dhash) <= 4 &&
        !left.decision.distinctFrom.includes(right.candidate.id) &&
        !right.decision.distinctFrom.includes(left.candidate.id)
      ) {
        throw new Error(
          `Resolve visual similarity before export: ${left.candidate.id} / ${right.candidate.id}`,
        );
      }
    }
  }
  const avatars: AvatarManifest["avatars"] = [];
  const files: PreparedCollection["files"][number][] = [];
  const seen = new Set<string>();
  for (const { candidate, decision } of approved) {
    const file = candidate.file;
    if (!file || seen.has(file.sha256)) continue;
    if (!new RegExp(`^images/${file.sha256}\\.(jpg|png|webp)$`, "u").test(file.path))
      throw new Error("Invalid local candidate path");
    const bytes = await readFile(join(directory, file.path));
    if (createHash("sha256").update(bytes).digest("hex") !== file.sha256)
      throw new Error(`Local file changed after review: ${candidate.id}`);
    const key = file.path.slice("images/".length);
    const metadata = structuredClone(decision.metadata);
    if (decision.originalSourceCheck)
      metadata.source.evidence += `\nOriginal page checked ${decision.originalSourceCheck.checkedAt}: ${decision.originalSourceCheck.evidence}`;
    metadata.source.evidence = `${metadata.source.evidence}\nCollection source: ${candidate.source.sourceId}; SHA-256: ${file.sha256}`;
    avatars.push({
      id: candidate.id,
      familyId: decision.familyId,
      sha256: file.sha256,
      url: new URL(key, base).href,
      enabled: true,
      reserved: false,
      metadata,
    });
    files.push({
      key,
      path: join(directory, file.path),
      byteLength: bytes.length,
      sha256: file.sha256,
      contentType: key.endsWith(".jpg")
        ? "image/jpeg"
        : key.endsWith(".png")
          ? "image/png"
          : "image/webp",
    });
    seen.add(file.sha256);
  }
  if (!avatars.length) throw new Error("No reviewed artwork to export");
  return { manifest: avatarManifestSchema.parse({ version: 2, avatars }), files };
}
