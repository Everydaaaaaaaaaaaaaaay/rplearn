import { z } from "zod";
import { assertSourceURL, sourceJSON } from "./network.js";
import { plainText, screenCommonsLicense } from "./rights.js";
import type { SearchPage, SourceImage } from "./types.js";

const openverseSchema = z.object({
  page: z.number().int().positive(),
  page_count: z.number().int().nonnegative(),
  results: z.array(
    z.object({
      id: z.uuid(),
      title: z.string().nullable(),
      foreign_landing_url: z.url(),
      url: z.url(),
      creator: z.string().nullable(),
      creator_url: z.string().nullable().optional(),
      license: z.string(),
      license_version: z.string(),
      license_url: z.url(),
      attribution: z.string(),
      source: z.string(),
      provider: z.string(),
      mature: z.boolean().optional(),
      unstable__sensitivity: z.array(z.unknown()).optional(),
      tags: z.array(z.object({ name: z.string() })).optional(),
      indexed_on: z.string().optional(),
    }),
  ),
});
export function parseOpenverse(value: unknown, offset: number): SearchPage {
  const data = openverseSchema.parse(value);
  return {
    images: data.results.map((item): SourceImage => {
      const label =
        item.license === "cc0"
          ? "CC0"
          : item.license === "by"
            ? `CC BY ${item.license_version}`
            : item.license;
      let eligible = false;
      let imageURL: string | null = null;
      try {
        // The index is not authority to fetch arbitrary remote hosts or approve rights.
        imageURL = assertSourceURL(item.url).href;
        eligible =
          screenCommonsLicense(label, item.license_url, "") &&
          !item.mature &&
          !item.unstable__sensitivity?.length;
      } catch {
        /* An unsupported image host stays as a discovery lead. */
      }
      return {
        sourceId: `openverse:${item.id}`,
        provider: "openverse",
        title: plainText(item.title ?? "Untitled"),
        creator: plainText(item.creator ?? "Unknown creator"),
        recordURL: item.foreign_landing_url,
        imageURL,
        licenseLabel: label,
        licenseURL: item.license_url,
        attribution: item.attribution,
        rightsScreen: eligible ? "eligible-for-review" : "manual-license-review",
        rightsReason:
          "Search-index license is a discovery lead only; verify the original creator page before approval. Unsupported licenses, hosts or sensitivity flags stay on hold.",
        evidence: {
          ...item,
          indexURL: `https://api.openverse.org/v1/images/${item.id}/`,
          originalPageReviewRequired: true,
        },
      };
    }),
    nextOffset:
      data.results.length && data.page < data.page_count
        ? offset + data.results.length
        : null,
  };
}

const metObjectSchema = z.object({
  objectID: z.number().int(),
  title: z.string(),
  objectURL: z.url(),
  isPublicDomain: z.boolean(),
  primaryImageSmall: z.string(),
  artistDisplayName: z.string(),
  culture: z.string(),
  objectDate: z.string(),
  rightsAndReproduction: z.string(),
  creditLine: z.string(),
});
export function parseMetObject(value: unknown): SourceImage {
  const item = metObjectSchema.parse(value);
  const eligible = item.isPublicDomain && !item.rightsAndReproduction.trim();
  return {
    sourceId: `met:${String(item.objectID)}`,
    provider: "met",
    title: item.title,
    creator: item.artistDisplayName.length
      ? item.artistDisplayName
      : "Unknown creator; The Metropolitan Museum of Art",
    recordURL: item.objectURL,
    imageURL: item.primaryImageSmall.length ? item.primaryImageSmall : null,
    licenseLabel: eligible ? "CC0" : "Rights require review",
    licenseURL: eligible ? "https://creativecommons.org/publicdomain/zero/1.0/" : null,
    attribution: `${item.title}, ${item.objectDate}. ${item.artistDisplayName}. The Metropolitan Museum of Art. ${item.creditLine}`,
    rightsScreen: eligible ? "eligible-for-review" : "manual-license-review",
    rightsReason:
      "Individual object isPublicDomain flag and rightsAndReproduction checked; collection-wide Open Access policy alone is insufficient",
    evidence: {
      ...item,
      policyURL:
        "https://www.metmuseum.org/about-the-met/policies-and-documents/open-access",
    },
  };
}

export async function searchExtendedSource(
  provider: "openverse" | "met",
  query: string,
  offset: number,
): Promise<SearchPage> {
  if (provider === "openverse") {
    const params = new URLSearchParams({
      q: query,
      license: "cc0,by",
      source: "flickr",
      page_size: "12",
      page: String(Math.floor(offset / 12) + 1),
      mature: "false",
    });
    return parseOpenverse(
      await sourceJSON(`https://api.openverse.org/v1/images/?${params.toString()}`),
      offset,
    );
  }
  const params = new URLSearchParams({ q: query, hasImages: "true" });
  const found = z
    .object({ objectIDs: z.array(z.number().int()).nullable() })
    .parse(
      await sourceJSON(
        `https://collectionapi.metmuseum.org/public/collection/v1/search?${params.toString()}`,
      ),
    );
  const ids = found.objectIDs ?? [];
  const images: SourceImage[] = [];
  // Small bounded pages respect the museum API and checkpoint only after a full page succeeds.
  for (const id of ids.slice(offset, offset + 4)) {
    images.push(
      parseMetObject(
        await sourceJSON(
          `https://collectionapi.metmuseum.org/public/collection/v1/objects/${String(id)}`,
        ),
      ),
    );
  }
  return { images, nextOffset: offset + 4 < ids.length ? offset + 4 : null };
}
