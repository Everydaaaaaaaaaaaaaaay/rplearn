import { createHash } from "node:crypto";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";
import sharp from "sharp";
import { S3Client, PutObjectCommand, GetObjectCommand } from "@aws-sdk/client-s3";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  collectCandidates,
  loadCollection,
} from "../../../src/modules/npc/collection/collector.js";
import {
  assertSourceURL,
  sourceBytes,
} from "../../../src/modules/npc/collection/network.js";
import {
  parseArtic,
  parseCommons,
  parseCleveland,
  screenCommonsLicense,
} from "../../../src/modules/npc/collection/sources.js";
import {
  collectionReport,
  reviewHTML,
} from "../../../src/modules/npc/collection/report.js";
import { prepareReviewedCollection } from "../../../src/modules/npc/collection/review.js";
import {
  createAvatarPublisher,
  publishCollection,
} from "../../../src/modules/npc/collection/publisher.js";
import {
  discoveryPlanSchema,
  reviewSchema,
  type SourceImage,
} from "../../../src/modules/npc/collection/types.js";
import {
  parseOpenverse,
  parseMetObject,
} from "../../../src/modules/npc/collection/extended-sources.js";
import { avatarMetadata } from "../../helpers/npc-avatars.js";

const source = (id: string): SourceImage => ({
  sourceId: `commons:${id}`,
  provider: "commons",
  title: "Shuttlecock",
  creator: "Artist",
  recordURL: "https://commons.wikimedia.org/wiki/File:Shuttlecock.jpg",
  imageURL: `https://upload.wikimedia.org/${id}.png`,
  licenseLabel: "CC0",
  licenseURL: "https://creativecommons.org/publicdomain/zero/1.0/",
  attribution: "Artist",
  rightsScreen: "eligible-for-review",
  rightsReason: "Test",
  evidence: { LicenseShortName: "CC0" },
});
const plan = discoveryPlanSchema.parse({
  version: 1,
  topics: [
    {
      id: "badminton",
      label: "羽毛球",
      domain: "sports",
      cultures: ["badminton"],
      target: 1,
      searches: [{ provider: "commons", query: "shuttlecock", language: "en" }],
    },
  ],
});
const directories: string[] = [];
async function directory() {
  const path = await mkdtemp(join(tmpdir(), "avatar-collection-test-"));
  directories.push(path);
  return path;
}
async function png() {
  return sharp({
    create: { width: 128, height: 160, channels: 3, background: "#48bfc0" },
  })
    .png()
    .toBuffer();
}

describe("avatar candidate acquisition", () => {
  afterEach(async () => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
    await Promise.all(
      directories.splice(0).map((path) => rm(path, { recursive: true, force: true })),
    );
  });
  it("checks exact licenses instead of accepting NC/ND, wrong domains or restrictions", () => {
    expect(
      screenCommonsLicense(
        "CC BY 4.0",
        "https://creativecommons.org/licenses/by/4.0/",
        "",
      ),
    ).toBe(true);
    expect(
      screenCommonsLicense(
        "CC BY 4.0",
        "https://creativecommons.org/licenses/by-nc/4.0/",
        "",
      ),
    ).toBe(false);
    expect(
      screenCommonsLicense(
        "CC0",
        "https://creativecommons.org.evil.test/publicdomain/zero/1.0/",
        "",
      ),
    ).toBe(false);
    expect(
      screenCommonsLicense(
        "CC0",
        "https://creativecommons.org/publicdomain/zero/1.0/",
        "Personality rights",
      ),
    ).toBe(false);
  });
  it("does not mistake museum metadata CC0 for the artwork license", () => {
    const page = parseArtic(
      {
        pagination: { total: 1 },
        data: [
          {
            id: 1,
            title: "Modern art",
            image_id: "abc",
            is_public_domain: false,
            api_link: "https://api.artic.edu/api/v1/artworks/1",
          },
        ],
      },
      0,
    );
    expect(page.images[0]?.rightsScreen).toBe("manual-license-review");
    expect(page.images[0]?.licenseURL).toBeNull();
    const cma = parseCleveland(
      {
        info: { total: 1 },
        data: [
          {
            id: 1,
            title: "Pottery",
            url: "https://www.clevelandart.org/art/1",
            share_license_status: "CC0",
            images: { web: { url: "https://openaccess-cdn.clevelandart.org/1.jpg" } },
          },
        ],
      },
      0,
    );
    expect(cma.images[0]?.rightsScreen).toBe("eligible-for-review");
  });
  it("screens Openverse's original URLs, licenses and sensitivity flags independently", () => {
    const indexed = {
      id: "f82fe9eb-5869-4acf-b824-82514c70c4c3",
      title: "Badminton",
      foreign_landing_url: "https://www.flickr.com/photos/example/1",
      url: "https://live.staticflickr.com/1/image.jpg",
      creator: "Artist",
      license: "by",
      license_version: "2.0",
      license_url: "https://creativecommons.org/licenses/by/2.0/",
      attribution: "Artist, CC BY 2.0",
      source: "flickr",
      provider: "flickr",
      mature: false,
    };
    const parse = (patch = {}) =>
      parseOpenverse(
        { page: 1, page_count: 2, results: [{ ...indexed, ...patch }] },
        0,
      );
    expect(parse().images[0]?.recordURL).toBe(indexed.foreign_landing_url);
    expect(parse().images[0]?.evidence.originalPageReviewRequired).toBe(true);
    expect(parse().nextOffset).toBe(1);
    expect(parse({ url: "https://127.0.0.1/private" }).images[0]?.imageURL).toBeNull();
    expect(parse({ license: "by-nc" }).images[0]?.rightsScreen).toBe(
      "manual-license-review",
    );
    expect(parse({ mature: true }).images[0]?.rightsScreen).toBe(
      "manual-license-review",
    );
  });
  it("uses the Met object's rights flag and preserves conflicting rights statements", () => {
    const object = {
      objectID: 1,
      title: "Chess piece",
      objectURL: "https://www.metmuseum.org/art/collection/search/1",
      isPublicDomain: true,
      primaryImageSmall: "https://images.metmuseum.org/chess.jpg",
      artistDisplayName: "",
      culture: "",
      objectDate: "1100",
      rightsAndReproduction: "",
      creditLine: "Museum collection",
    };
    expect(parseMetObject(object).rightsScreen).toBe("eligible-for-review");
    expect(parseMetObject({ ...object, isPublicDomain: false }).licenseURL).toBeNull();
    expect(
      parseMetObject({ ...object, rightsAndReproduction: "Third party rights" })
        .rightsScreen,
    ).toBe("manual-license-review");
  });
  it("preserves source evidence and continuation, and treats API errors as retryable", () => {
    expect(() => parseCommons({ error: { code: "maxlag", info: "busy" } })).toThrow(
      "maxlag",
    );
    const page = parseCommons({
      continue: { gsroffset: 12 },
      query: {
        pages: {
          "1": {
            pageid: 1,
            title: "File:Ball.jpg",
            imageinfo: [
              {
                url: "https://upload.wikimedia.org/1.jpg",
                descriptionurl: "https://commons.wikimedia.org/wiki/File:Ball.jpg",
                width: 100,
                height: 100,
                extmetadata: {
                  Artist: { value: "<b>Artist</b>" },
                  LicenseShortName: { value: "CC0" },
                  LicenseUrl: {
                    value: "https://creativecommons.org/publicdomain/zero/1.0/",
                  },
                },
              },
            ],
          },
        },
      },
    });
    expect(page.nextOffset).toBe(12);
    expect(page.images[0]?.creator).toBe("Artist");
    expect(page.images[0]?.evidence.Artist).toBe("<b>Artist</b>");
  });
  it("rejects off-provider redirects before making a second request", async () => {
    expect(() => assertSourceURL("https://localhost/file")).toThrow();
    const fetch = vi.fn(() =>
      Promise.resolve(
        new Response(null, {
          status: 302,
          headers: { location: "http://127.0.0.1/private" },
        }),
      ),
    );
    vi.stubGlobal("fetch", fetch);
    await expect(sourceBytes("https://upload.wikimedia.org/a.jpg")).rejects.toThrow(
      "Unapproved",
    );
    expect(fetch).toHaveBeenCalledTimes(1);
  });
  it("resumes a failed search without advancing the cursor and does not redownload completed work", async () => {
    const out = await directory();
    const bytes = await png();
    const search = vi
      .fn()
      .mockRejectedValueOnce(new Error("temporary outage"))
      .mockResolvedValue({ images: [source("one")], nextOffset: null });
    const download = vi.fn(() => Promise.resolve(bytes));
    const options = { outputDirectory: out, maxPagesPerSearch: 1, maxDownloads: 4 };
    await collectCandidates(plan, options, { search, download });
    expect(Object.values((await loadCollection(out)).searches)[0]?.offset).toBe(0);
    const state = await collectCandidates(plan, options, { search, download });
    const candidate = Object.values(state.candidates)[0];
    expect(candidate?.file?.sha256).toBe(
      createHash("sha256").update(bytes).digest("hex"),
    );
    expect(collectionReport(plan, state).approved).toBe(0);
    await collectCandidates(plan, options, { search, download });
    expect(search).toHaveBeenCalledTimes(2);
    expect(download).toHaveBeenCalledTimes(1);
  });
  it("blocks missing reviews and altered bytes before any upload", async () => {
    const out = await directory();
    const bytes = await png();
    const state = await collectCandidates(
      plan,
      { outputDirectory: out, maxPagesPerSearch: 1, maxDownloads: 2 },
      {
        search: () => Promise.resolve({ images: [source("one")], nextOffset: null }),
        download: () => Promise.resolve(bytes),
      },
    );
    const candidate = Object.values(state.candidates)[0];
    if (!candidate?.file) throw new Error("Missing fixture image");
    await expect(
      prepareReviewedCollection(
        out,
        state,
        { version: 1, decisions: [] },
        "https://cdn.example.com/npc/",
      ),
    ).rejects.toThrow("No reviewed");
    const review = reviewSchema.parse({
      version: 1,
      decisions: [
        {
          decision: "approve",
          candidateId: candidate.id,
          sha256: candidate.file.sha256,
          familyId: candidate.id,
          metadata: {
            ...avatarMetadata,
            source: {
              ...avatarMetadata.source,
              kind: "licensed",
              license: candidate.source.licenseLabel,
              pageUrl: candidate.source.recordURL,
              licenseUrl: candidate.source.licenseURL,
            },
          },
        },
      ],
    });
    const prepared = await prepareReviewedCollection(
      out,
      state,
      review,
      "https://cdn.example.com/npc/",
    );
    expect(prepared.manifest.avatars[0]?.enabled).toBe(true);
    candidate.source = { ...candidate.source, provider: "openverse" };
    await expect(
      prepareReviewedCollection(out, state, review, "https://cdn.example.com/npc/"),
    ).rejects.toThrow("original creator-page verification");
    candidate.source = { ...candidate.source, provider: "commons" };
    const put = vi.fn(() => Promise.resolve());
    await publishCollection(prepared, { put });
    expect(put).toHaveBeenCalledTimes(1);
    const html = reviewHTML(plan, state);
    expect(html).toContain("尚未批准入库");
    expect(html).not.toContain("<script");
    await writeFile(join(out, candidate.file.path), "substituted");
    await expect(
      prepareReviewedCollection(out, state, review, "https://cdn.example.com/npc/"),
    ).rejects.toThrow("changed");
    expect(
      JSON.parse(await readFile(join(out, "collection.json"), "utf8")),
    ).toHaveProperty("version", 1);
  });
  it("shares download budgets across topics and prioritizes fresh alternatives on retry", async () => {
    const out = await directory();
    const twoTopics = discoveryPlanSchema.parse({
      version: 1,
      topics: [
        { ...plan.topics[0], target: 2 },
        {
          ...plan.topics[0],
          id: "pottery",
          target: 2,
          searches: [{ provider: "commons", query: "pottery", language: "en" }],
        },
      ],
    });
    const bytes = await png();
    const order: string[] = [];
    const search = vi.fn((_provider: string, query: string) =>
      Promise.resolve({
        images: [source(query + "-one"), source(query + "-two")],
        nextOffset: null,
      }),
    );
    const download = vi.fn((url: string) => {
      order.push(url);
      return url.includes("one")
        ? Promise.reject(new Error("outage"))
        : Promise.resolve(bytes);
    });
    const options = { outputDirectory: out, maxPagesPerSearch: 1, maxDownloads: 2 };
    await collectCandidates(twoTopics, options, { search, download });
    expect(order).toEqual([
      "https://upload.wikimedia.org/shuttlecock-one.png",
      "https://upload.wikimedia.org/pottery-one.png",
    ]);
    await collectCandidates(twoTopics, options, { search, download });
    expect(order.slice(2)).toEqual([
      "https://upload.wikimedia.org/shuttlecock-two.png",
      "https://upload.wikimedia.org/pottery-two.png",
    ]);
  });
  it("invalidates corrupt files before deciding whether to search again", async () => {
    const out = await directory();
    const bytes = await png();
    const search = vi.fn(() =>
      Promise.resolve({ images: [source("one")], nextOffset: 12 }),
    );
    const download = vi.fn(() => Promise.resolve(bytes));
    const options = { outputDirectory: out, maxPagesPerSearch: 1, maxDownloads: 1 };
    const state = await collectCandidates(plan, options, { search, download });
    const file = Object.values(state.candidates)[0]?.file;
    if (!file) throw new Error("Missing fixture");
    await writeFile(join(out, file.path), "broken");
    await collectCandidates(plan, options, { search, download });
    expect(search).toHaveBeenCalledTimes(2);
    expect(download).toHaveBeenCalledTimes(2);
  });
  it("prevents identical and near-identical files receiving unrelated families", async () => {
    const out = await directory();
    const bytes = await png();
    const state = await collectCandidates(
      { ...plan, topics: plan.topics.map((topic) => ({ ...topic, target: 3 })) },
      { outputDirectory: out, maxPagesPerSearch: 1, maxDownloads: 3 },
      {
        search: () =>
          Promise.resolve({ images: [source("one"), source("two")], nextOffset: null }),
        download: () => Promise.resolve(bytes),
      },
    );
    const decisions = Object.values(state.candidates).map((candidate) => ({
      decision: "approve",
      candidateId: candidate.id,
      sha256: candidate.file?.sha256,
      familyId: candidate.id,
      metadata: {
        ...avatarMetadata,
        source: {
          ...avatarMetadata.source,
          kind: "licensed",
          license: "CC0",
          pageUrl: candidate.source.recordURL,
          licenseUrl: candidate.source.licenseURL,
        },
      },
    }));
    const review = reviewSchema.parse({ version: 1, decisions });
    await expect(
      prepareReviewedCollection(out, state, review, "https://cdn.example.com/"),
    ).rejects.toThrow("Identical bytes");
    const first = review.decisions[0];
    const second = review.decisions[1];
    if (first?.decision !== "approve" || second?.decision !== "approve")
      throw new Error("Missing decisions");
    second.familyId = first.familyId;
    expect(
      (await prepareReviewedCollection(out, state, review, "https://cdn.example.com/"))
        .files,
    ).toHaveLength(1);
    const secondCandidate = state.candidates[second.candidateId];
    if (!secondCandidate?.file) throw new Error("Missing file");
    secondCandidate.file.sha256 = "b".repeat(64);
    second.sha256 = secondCandidate.file.sha256;
    second.familyId = second.candidateId;
    await expect(
      prepareReviewedCollection(out, state, review, "https://cdn.example.com/"),
    ).rejects.toThrow("Resolve visual similarity");
  });
  it("never overwrites a published object and verifies bytes on upload retry", async () => {
    const out = await directory();
    const bytes = await png();
    const path = join(out, "image.png");
    await writeFile(path, bytes);
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    const file = {
      path,
      sha256,
      key: sha256 + ".png",
      byteLength: bytes.length,
      contentType: "image/png",
    };
    const send = vi
      .spyOn(
        S3Client.prototype as unknown as {
          send(command: PutObjectCommand | GetObjectCommand): Promise<unknown>;
        },
        "send",
      )
      .mockRejectedValueOnce({ $metadata: { httpStatusCode: 412 } })
      .mockResolvedValueOnce({
        ContentLength: bytes.length,
        Body: { transformToByteArray: () => Promise.resolve(bytes) },
      });
    const publisher = createAvatarPublisher({
      bucket: "test-avatars",
      prefix: "npc",
      region: "us-east-1",
    });
    await publisher.put(file);
    expect(send.mock.calls[0]?.[0]).toBeInstanceOf(PutObjectCommand);
    expect(send.mock.calls[0]?.[0].input).toMatchObject({
      IfNoneMatch: "*",
      Key: "npc/" + file.key,
    });
    expect(send.mock.calls[1]?.[0]).toBeInstanceOf(GetObjectCommand);
    send
      .mockRejectedValueOnce({ $metadata: { httpStatusCode: 412 } })
      .mockResolvedValueOnce({
        ContentLength: bytes.length,
        Body: {
          transformToByteArray: () => Promise.resolve(Buffer.alloc(bytes.length)),
        },
      });
    await expect(publisher.put(file)).rejects.toThrow("Existing object differs");
    await writeFile(path, "changed after prepare");
    await expect(publisher.put(file)).rejects.toThrow("changed before upload");
    expect(send).toHaveBeenCalledTimes(4);
  });
});
