import { z } from "zod";
import { searchExtendedSource } from "./extended-sources.js";
import { plainText, screenCommonsLicense } from "./rights.js";
export { screenCommonsLicense } from "./rights.js";
import { sourceJSON } from "./network.js";
import type { Provider, SearchPage, SourceImage } from "./types.js";

export const sourceReferences = {
  commons:
    "https://commons.wikimedia.org/wiki/Commons:Reusing_content_outside_Wikimedia",
  cleveland: "https://www.clevelandart.org/open-access",
  artic: "https://www.artic.edu/open-access/open-access-images",
} as const;
const string = z.string();
const commonsSchema = z.object({
  error: z.object({ code: string, info: string }).optional(),
  continue: z.object({ gsroffset: z.number() }).optional(),
  query: z
    .object({
      pages: z.record(
        string,
        z.object({
          pageid: z.number(),
          title: string,
          imageinfo: z
            .array(
              z.object({
                url: string,
                thumburl: string.optional(),
                descriptionurl: string,
                width: z.number(),
                height: z.number(),
                extmetadata: z.record(
                  string,
                  z.object({ value: z.union([string, z.number()]) }),
                ),
              }),
            )
            .optional(),
        }),
      ),
    })
    .optional(),
});
export function parseCommons(value: unknown): SearchPage {
  const data = commonsSchema.parse(value);
  if (data.error) throw new Error(`Commons ${data.error.code}: ${data.error.info}`);
  const images: SourceImage[] = [];
  for (const page of Object.values(data.query?.pages ?? {})) {
    const info = page.imageinfo?.[0];
    if (!info) continue;
    const field = (name: string) => String(info.extmetadata[name]?.value ?? "");
    const title = plainText(page.title.replace(/^File:/u, ""));
    const creator = plainText(field("Artist"));
    const license = plainText(field("LicenseShortName"));
    const licenseURL = field("LicenseUrl") || null;
    let eligible = false;
    try {
      eligible = screenCommonsLicense(license, licenseURL, field("Restrictions"));
    } catch {
      /* malformed license URL stays on hold */
    }
    images.push({
      sourceId: `commons:${String(page.pageid)}`,
      provider: "commons",
      title,
      creator,
      recordURL: info.descriptionurl,
      imageURL: info.thumburl ?? info.url,
      licenseLabel: license,
      licenseURL,
      attribution: `${title} — ${creator}. ${license}. ${info.descriptionurl}`,
      rightsScreen: eligible ? "eligible-for-review" : "manual-license-review",
      rightsReason: eligible
        ? "Source label and canonical CC0/CC BY URL agree; individual image review still required"
        : "License missing, outside automatic shortlist, or source lists restrictions",
      evidence: {
        api: "https://commons.wikimedia.org/w/api.php",
        pageId: page.pageid,
        originalURL: info.url,
        policyURL: sourceReferences.commons,
        ...Object.fromEntries(
          [
            "LicenseShortName",
            "LicenseUrl",
            "UsageTerms",
            "AttributionRequired",
            "Attribution",
            "Credit",
            "Copyright",
            "Permission",
            "Restrictions",
            "Artist",
            "ImageDescription",
            "Categories",
          ].map((key) => [key, field(key)]),
        ),
      },
    });
  }
  return { images, nextOffset: data.continue?.gsroffset ?? null };
}

const cmaSchema = z.object({
  info: z.object({ total: z.number() }),
  data: z.array(
    z.object({
      id: z.number(),
      title: string,
      url: string,
      share_license_status: string,
      creation_date: string.nullable().optional(),
      culture: z.array(string).optional(),
      technique: string.optional(),
      tombstone: string.optional(),
      creators: z.array(z.object({ description: string })).optional(),
      images: z
        .object({ web: z.object({ url: string }).nullable().optional() })
        .nullable()
        .optional(),
    }),
  ),
});
export function parseCleveland(value: unknown, offset: number): SearchPage {
  const data = cmaSchema.parse(value);
  return {
    images: data.data.map((item) => ({
      sourceId: `cleveland:${String(item.id)}`,
      provider: "cleveland",
      title: item.title,
      creator: item.creators?.length
        ? item.creators.map((creator) => creator.description).join("; ")
        : "Unknown creator",
      recordURL: item.url,
      imageURL: item.images?.web?.url ?? null,
      licenseLabel: item.share_license_status,
      licenseURL:
        item.share_license_status === "CC0"
          ? "https://creativecommons.org/publicdomain/zero/1.0/"
          : null,
      attribution: item.tombstone ?? `${item.title} — The Cleveland Museum of Art`,
      rightsScreen:
        item.share_license_status === "CC0"
          ? "eligible-for-review"
          : "manual-license-review",
      rightsReason:
        "Individual collection record's share_license_status; not the API metadata license",
      evidence: { ...item, policyURL: sourceReferences.cleveland },
    })),
    nextOffset:
      data.data.length > 0 && offset + data.data.length < data.info.total
        ? offset + data.data.length
        : null,
  };
}

const articSchema = z.object({
  pagination: z.object({ total: z.number() }),
  data: z.array(
    z.object({
      id: z.number(),
      title: string,
      image_id: string.nullable(),
      is_public_domain: z.boolean(),
      artist_display: string.optional(),
      date_display: string.optional(),
      place_of_origin: string.nullable().optional(),
      api_link: string,
    }),
  ),
});
export function parseArtic(value: unknown, offset: number): SearchPage {
  const data = articSchema.parse(value);
  return {
    images: data.data.map((item) => ({
      sourceId: `artic:${String(item.id)}`,
      provider: "artic",
      title: item.title,
      creator: item.artist_display ?? "Unknown creator",
      recordURL: `https://www.artic.edu/artworks/${String(item.id)}`,
      imageURL: item.image_id
        ? `https://www.artic.edu/iiif/2/${encodeURIComponent(item.image_id)}/full/843,/0/default.jpg`
        : null,
      licenseLabel: item.is_public_domain ? "CC0" : "Copyright restricted",
      licenseURL: item.is_public_domain
        ? "https://creativecommons.org/publicdomain/zero/1.0/"
        : null,
      attribution: `${item.title} — ${item.artist_display ?? "Unknown creator"}. Art Institute of Chicago`,
      rightsScreen: item.is_public_domain
        ? "eligible-for-review"
        : "manual-license-review",
      rightsReason:
        "Individual artwork's is_public_domain flag; API metadata CC0 alone is insufficient",
      evidence: { ...item, policyURL: sourceReferences.artic },
    })),
    nextOffset:
      data.data.length > 0 && offset + data.data.length < data.pagination.total
        ? offset + data.data.length
        : null,
  };
}

export async function searchSource(
  provider: Provider,
  query: string,
  offset: number,
): Promise<SearchPage> {
  if (provider === "openverse" || provider === "met")
    return searchExtendedSource(provider, query, offset);
  if (provider === "commons") {
    const params = new URLSearchParams({
      action: "query",
      format: "json",
      generator: "search",
      gsrsearch: `${query} filetype:bitmap`,
      gsrnamespace: "6",
      gsrlimit: "12",
      gsroffset: String(offset),
      prop: "imageinfo",
      iiprop: "url|extmetadata|size",
      iiurlwidth: "512",
    });
    return parseCommons(
      await sourceJSON(`https://commons.wikimedia.org/w/api.php?${params.toString()}`),
    );
  }
  if (provider === "cleveland") {
    const params = new URLSearchParams({
      search: query,
      has_image: "1",
      cc0: "1",
      limit: "8",
      skip: String(offset),
    });
    return parseCleveland(
      await sourceJSON(
        `https://openaccess-api.clevelandart.org/api/artworks/?${params.toString()}`,
      ),
      offset,
    );
  }
  const params = new URLSearchParams({
    q: query,
    limit: "8",
    page: String(Math.floor(offset / 8) + 1),
    fields:
      "id,title,image_id,is_public_domain,artist_display,date_display,place_of_origin,api_link",
  });
  return parseArtic(
    await sourceJSON(
      `https://api.artic.edu/api/v1/artworks/search?${params.toString()}`,
    ),
    offset,
  );
}
