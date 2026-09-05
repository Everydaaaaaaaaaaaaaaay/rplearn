import { createHash } from "node:crypto";
import type { ReadableStreamDefaultReader } from "node:stream/web";

// Check the actual served bytes before publication, not only a manifest's claimed checksum.
export async function verifyAvatarFile(
  url: string,
  expectedSha256: string,
): Promise<void> {
  const response = await fetch(url, {
    redirect: "error",
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok || !response.body)
    throw new Error(`Avatar download failed: ${response.status.toString()}`);
  const maximum = 5 * 1024 * 1024;
  const hash = createHash("sha256");
  const reader = response.body.getReader() as ReadableStreamDefaultReader<Uint8Array>;
  let size = 0;
  let header = Buffer.alloc(0);
  try {
    let chunk = await reader.read();
    while (!chunk.done) {
      const value = chunk.value;
      size += value.length;
      if (size > maximum) throw new Error("Avatar exceeds 5 MiB");
      if (header.length < 12) header = Buffer.concat([header, value]).subarray(0, 12);
      hash.update(value);
      chunk = await reader.read();
    }
  } finally {
    await reader.cancel();
  }
  const png = header
    .subarray(0, 8)
    .equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
  const jpeg = header[0] === 255 && header[1] === 216 && header[2] === 255;
  const webp =
    header.toString("ascii", 0, 4) === "RIFF" &&
    header.toString("ascii", 8, 12) === "WEBP";
  if (!png && !jpeg && !webp) throw new Error("Avatar must be PNG, JPEG or WebP");
  if (hash.digest("hex") !== expectedSha256)
    throw new Error("Avatar SHA-256 does not match manifest");
}
