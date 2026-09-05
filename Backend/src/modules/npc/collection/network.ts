import type { ReadableStreamDefaultReader } from "node:stream/web";
import { setTimeout } from "node:timers/promises";

const hosts = new Set([
  "commons.wikimedia.org",
  "upload.wikimedia.org",
  "thumb.wikimedia.org",
  "openaccess-api.clevelandart.org",
  "openaccess-cdn.clevelandart.org",
  "api.artic.edu",
  "www.artic.edu",
  "api.openverse.org",
  "live.staticflickr.com",
  "collectionapi.metmuseum.org",
  "images.metmuseum.org",
]);
export function assertSourceURL(value: string): URL {
  const url = new URL(value);
  if (
    url.protocol !== "https:" ||
    url.username ||
    url.password ||
    url.port ||
    !hosts.has(url.hostname)
  ) {
    throw new Error(`Unapproved source URL: ${url.hostname}`);
  }
  return url;
}

export async function sourceBytes(
  value: string,
  maximum = 5 * 1024 * 1024,
): Promise<Buffer> {
  let url = assertSourceURL(value);
  for (let redirects = 0; redirects < 4; redirects += 1) {
    let response: Response | undefined;
    for (let attempt = 0; attempt < 3; attempt += 1) {
      response = await fetch(url, {
        headers: {
          "user-agent":
            "LingoTripAvatarCollector/0.1 (operator-run open-culture research)",
        },
        redirect: "manual",
        signal: AbortSignal.timeout(20000),
      });
      if (response.status !== 429 && response.status < 500) break;
      await response.body?.cancel();
      if (attempt === 2) throw new Error(`Source HTTP ${String(response.status)}`);
      const delay = Number(response.headers.get("retry-after"));
      await setTimeout(
        Number.isFinite(delay) && delay > 0
          ? Math.min(delay, 20) * 1000
          : (attempt + 1) * 1500,
      );
    }
    if (!response) throw new Error("Source returned no response");
    if ([301, 302, 303, 307, 308].includes(response.status)) {
      const location = response.headers.get("location");
      await response.body?.cancel();
      if (!location) throw new Error("Redirect missing Location");
      url = assertSourceURL(new URL(location, url).href);
      continue;
    }
    if (!response.ok || !response.body)
      throw new Error(`Source HTTP ${String(response.status)}`);
    const reader = response.body.getReader() as ReadableStreamDefaultReader<Uint8Array>;
    const chunks: Uint8Array[] = [];
    let length = 0;
    try {
      let chunk = await reader.read();
      while (!chunk.done) {
        length += chunk.value.length;
        if (length > maximum)
          throw new Error(`Source exceeds ${String(maximum)} bytes`);
        chunks.push(chunk.value);
        chunk = await reader.read();
      }
    } finally {
      await reader.cancel();
    }
    return Buffer.concat(chunks);
  }
  throw new Error("Too many source redirects");
}
export async function sourceJSON(url: string): Promise<unknown> {
  return JSON.parse(
    (await sourceBytes(url, 4 * 1024 * 1024)).toString("utf8"),
  ) as unknown;
}
