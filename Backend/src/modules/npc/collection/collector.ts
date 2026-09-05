import { createHash } from "node:crypto";
import { mkdir, open, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { v5 as uuidv5 } from "uuid";
import { inspectImage } from "./images.js";
import { sourceBytes } from "./network.js";
import { searchSource } from "./sources.js";
import { collectionStateSchema } from "./types.js";
import type {
  Candidate,
  CollectionOptions,
  CollectionState,
  DiscoveryPlan,
} from "./types.js";

const namespace = "145d2135-96cf-4a8e-a310-185c168563ab";
export function candidateId(sourceId: string): string {
  return uuidv5(sourceId, namespace);
}
export async function atomicJSON(path: string, value: unknown): Promise<void> {
  const temporary = `${path}.${String(process.pid)}.tmp`;
  await writeFile(temporary, JSON.stringify(value, null, 2) + "\n", { mode: 0o600 });
  await rename(temporary, path);
}
export async function loadCollection(directory: string): Promise<CollectionState> {
  try {
    return collectionStateSchema.parse(
      JSON.parse(await readFile(join(directory, "collection.json"), "utf8")) as unknown,
    );
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT")
      return { version: 1, candidates: {}, searches: {} };
    throw error;
  }
}
export async function withCollectionLock<T>(
  directory: string,
  work: () => Promise<T>,
): Promise<T> {
  await mkdir(directory, { recursive: true });
  const lockPath = join(directory, ".collection.lock");
  const lock = await open(lockPath, "wx").catch((error: unknown) => {
    if ((error as NodeJS.ErrnoException).code === "EEXIST") {
      throw new Error(
        "Collector lock exists. Check its PID before removing a stale .collection.lock; never run two writers.",
      );
    }
    throw error;
  });
  try {
    await lock.writeFile(String(process.pid));
    return await work();
  } finally {
    await lock.close();
    await unlink(lockPath);
  }
}
export async function collectCandidates(
  plan: DiscoveryPlan,
  options: CollectionOptions,
  dependencies = { search: searchSource, download: sourceBytes },
  progress: (message: string) => void = () => undefined,
  finalize: (state: CollectionState) => Promise<void> = () => Promise.resolve(),
): Promise<CollectionState> {
  return withCollectionLock(options.outputDirectory, async () => {
    const state = await loadCollection(options.outputDirectory);
    const checkpoint = () =>
      atomicJSON(join(options.outputDirectory, "collection.json"), state);
    // Validate before quotas: a missing file must not suppress a needed search.
    for (const candidate of Object.values(state.candidates)) {
      if (!candidate.file) continue;
      try {
        const bytes = await readFile(
          join(options.outputDirectory, candidate.file.path),
        );
        if (createHash("sha256").update(bytes).digest("hex") === candidate.file.sha256)
          continue;
      } catch {
        /* missing local content is eligible for another download */
      }
      delete candidate.file;
      candidate.downloadError = "Local file missing or changed";
    }
    await checkpoint();
    for (const topic of plan.topics) {
      const existing = Object.values(state.candidates).filter(
        (candidate) => candidate.topicIds.includes(topic.id) && candidate.file,
      );
      if (
        new Set(existing.map((candidate) => candidate.file?.sha256)).size >=
        topic.target
      )
        continue;
      for (const search of topic.searches) {
        const key = createHash("sha256")
          .update(
            JSON.stringify([topic.id, search.provider, search.query, search.language]),
          )
          .digest("hex");
        const cursor = state.searches[key] ?? { offset: 0, exhausted: false, pages: 0 };
        for (
          let page = 0;
          page < options.maxPagesPerSearch && !cursor.exhausted;
          page += 1
        ) {
          try {
            const result = await dependencies.search(
              search.provider,
              search.query,
              cursor.offset,
            );
            for (const image of result.images) {
              const id = candidateId(image.sourceId);
              const candidate: Candidate = state.candidates[id] ?? {
                id,
                source: image,
                discoveredAt: new Date().toISOString(),
                topicIds: [],
              };
              if (!candidate.topicIds.includes(topic.id))
                candidate.topicIds.push(topic.id);
              state.candidates[id] = candidate;
            }
            cursor.pages += 1;
            cursor.exhausted =
              result.nextOffset === null || result.nextOffset <= cursor.offset;
            cursor.offset = result.nextOffset ?? cursor.offset;
            delete cursor.error;
            state.searches[key] = cursor;
            await checkpoint();
            progress(
              `${topic.id}/${search.provider}: ${String(result.images.length)} records`,
            );
          } catch (error) {
            cursor.error = error instanceof Error ? error.message : String(error);
            state.searches[key] = cursor;
            await checkpoint();
            progress(`${topic.id}/${search.provider}: retryable error ${cursor.error}`);
            break;
          }
        }
      }
    }
    await mkdir(join(options.outputDirectory, "images"), { recursive: true });
    // Round-robin by topic: downloading the first N API results would starve later cultures.
    const queue = new Map<string, Candidate>();
    const eligible = Object.values(state.candidates).filter(
      (candidate) =>
        candidate.source.rightsScreen === "eligible-for-review" &&
        candidate.source.imageURL,
    );
    const groups = plan.topics.map((topic) =>
      eligible
        .filter((candidate) => candidate.topicIds.includes(topic.id))
        // New alternatives get a chance before an earlier failing provider uses the budget.
        .sort(
          (left, right) => Number(!!left.downloadError) - Number(!!right.downloadError),
        ),
    );
    const largest = Math.max(0, ...groups.map((group) => group.length));
    for (let index = 0; index < largest; index += 1) {
      for (const group of groups) {
        const candidate = group[index];
        if (candidate) queue.set(candidate.id, candidate);
      }
    }
    let downloaded = 0;
    let attempted = 0;
    for (const candidate of queue.values()) {
      if (candidate.file) continue;
      const needed = plan.topics.some(
        (topic) =>
          candidate.topicIds.includes(topic.id) &&
          new Set(
            Object.values(state.candidates)
              .filter((entry) => entry.topicIds.includes(topic.id) && entry.file)
              .map((entry) => entry.file?.sha256),
          ).size < topic.target,
      );
      if (!needed) continue;
      if (attempted >= options.maxDownloads) break;
      attempted += 1;
      try {
        const url = candidate.source.imageURL;
        if (!url) continue;
        const bytes = await dependencies.download(url);
        const { extension, ...metadata } = await inspectImage(bytes);
        const path = `images/${metadata.sha256}.${extension}`;
        await writeFile(join(options.outputDirectory, path), bytes, { mode: 0o600 });
        candidate.file = { path, ...metadata };
        delete candidate.downloadError;
        downloaded += 1;
        progress(`Downloaded ${String(downloaded)}: ${candidate.source.title}`);
      } catch (error) {
        candidate.downloadError =
          error instanceof Error ? error.message : String(error);
        progress(
          `Download deferred: ${candidate.source.title}: ${candidate.downloadError}`,
        );
      }
      await checkpoint();
    }
    await finalize(state);
    return state;
  });
}
