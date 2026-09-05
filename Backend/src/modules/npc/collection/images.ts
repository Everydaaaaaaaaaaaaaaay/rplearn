import { createHash } from "node:crypto";
import sharp from "sharp";

export async function inspectImage(bytes: Buffer) {
  const decoder = sharp(bytes, { limitInputPixels: 40_000_000, failOn: "warning" });
  const metadata = await decoder.metadata();
  if (!["jpeg", "png", "webp"].includes(metadata.format) || (metadata.pages ?? 1) > 1) {
    throw new Error("Only static JPEG, PNG and WebP candidates are supported");
  }
  if (
    !metadata.width ||
    !metadata.height ||
    Math.min(metadata.width, metadata.height) < 96
  ) {
    throw new Error("Image is too small for an avatar");
  }
  // Analysis only: downloaded artwork is never silently cropped or rewritten.
  const pixels = await decoder
    .clone()
    .rotate()
    .flatten({ background: "#ffffff" })
    .removeAlpha()
    .resize(9, 8, { fit: "fill" })
    .greyscale()
    .raw()
    .toBuffer();
  let dhash = 0n;
  for (let row = 0; row < 8; row += 1) {
    for (let col = 0; col < 8; col += 1) {
      dhash =
        (dhash << 1n) |
        ((pixels[row * 9 + col] ?? 0) > (pixels[row * 9 + col + 1] ?? 0) ? 1n : 0n);
    }
  }
  return {
    sha256: createHash("sha256").update(bytes).digest("hex"),
    dhash: dhash.toString(16).padStart(16, "0"),
    width: metadata.width,
    height: metadata.height,
    cropRetention:
      Math.min(metadata.width, metadata.height) /
      Math.max(metadata.width, metadata.height),
    bytes: bytes.length,
    extension: metadata.format === "jpeg" ? "jpg" : metadata.format,
  };
}
export function hashDistance(left: string, right: string): number {
  let bits = BigInt(`0x${left}`) ^ BigInt(`0x${right}`);
  let distance = 0;
  while (bits !== 0n) {
    bits &= bits - 1n;
    distance += 1;
  }
  return distance;
}
