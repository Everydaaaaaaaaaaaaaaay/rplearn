import { createHash } from "node:crypto";
import { Readable } from "node:stream";
import { crc32, inflateSync } from "node:zlib";
import { z } from "zod";
import type { MediaObjectStore } from "../media/object-store.js";
import { AppError } from "../../shared/errors.js";

export const learningImageSchema = z.strictObject({
  id: z.string().regex(/^image\.[a-f0-9]{64}$/),
  sha256: z.string().regex(/^[a-f0-9]{64}$/),
  byteSize: z.number().int().min(64).max(2_000_000),
  width: z.number().int().min(128).max(1024),
  height: z.number().int().min(128).max(1024),
  contentType: z.literal("image/png"),
  description: z.string().trim().min(5).max(1000),
  source: z.string().trim().min(8).max(2000),
  reviewedBy: z.string().trim().min(1).max(100),
  reviewedAt: z.iso.date(),
  reviewNotes: z.string().trim().min(20).max(2000),
});
export type LearningImageAsset = z.infer<typeof learningImageSchema>;
export type PreparedLearningImage = Readonly<{
  metadata: LearningImageAsset;
  bytes: Buffer;
}>;
export type DeferredLearningImage = Readonly<{
  metadata: LearningImageAsset;
  loadBytes: () => Promise<Buffer>;
}>;
export type LearningImageObjectStore = Pick<
  MediaObjectStore,
  "createDownloadUrl" | "createUploadUrl" | "headObject"
>;
export const learningImageObjectKey = (id: string) => `learning/images/${id}.png`;

/** 只收有界、单帧、8位 RGB/RGBA PNG；CRC、解压长度和扫描行都必须与尺寸一致。 */
export function verifyLearningImage(value: LearningImageAsset, bytes: Buffer): void {
  const metadata = learningImageSchema.parse(value);
  const fail: () => never = () => {
    throw new Error(`图片资源 ${metadata.id} 的文件、格式或审核元数据不一致。`);
  };
  if (
    bytes.length !== metadata.byteSize ||
    metadata.id !== `image.${metadata.sha256}` ||
    createHash("sha256").update(bytes).digest("hex") !== metadata.sha256 ||
    !bytes.subarray(0, 8).equals(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]))
  )
    fail();
  let position = 8,
    channels = 0,
    ended = false,
    dataEnded = false;
  const compressed: Buffer[] = [];
  while (position + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(position),
      start = position + 8,
      end = start + length;
    if (end + 4 > bytes.length) fail();
    const kind = bytes.toString("ascii", position + 4, start);
    if (crc32(bytes.subarray(position + 4, end)) !== bytes.readUInt32BE(end)) fail();
    if (position === 8 && kind !== "IHDR") fail();
    if (kind === "IHDR") {
      if (
        position !== 8 ||
        length !== 13 ||
        bytes.readUInt32BE(start) !== metadata.width ||
        bytes.readUInt32BE(start + 4) !== metadata.height ||
        bytes[start + 8] !== 8 ||
        ![2, 6].includes(bytes[start + 9] ?? -1) ||
        bytes[start + 10] !== 0 ||
        bytes[start + 11] !== 0 ||
        bytes[start + 12] !== 0
      )
        fail();
      channels = bytes[start + 9] === 6 ? 4 : 3;
    } else if (kind === "IDAT") {
      if (dataEnded) fail();
      compressed.push(bytes.subarray(start, end));
    } else if (kind === "IEND") {
      if (length !== 0 || end + 4 !== bytes.length || compressed.length === 0) fail();
      ended = true;
    } else {
      // 禁止动画和未知关键块；普通色彩/来源等辅助块不参与像素解码。
      if (["acTL", "fcTL", "fdAT"].includes(kind) || !/^[a-z][A-Za-z]{3}$/.test(kind))
        fail();
      if (compressed.length > 0) dataEnded = true;
    }
    position = end + 4;
  }
  if (!ended || position !== bytes.length || channels === 0) fail();
  const stride = 1 + metadata.width * channels,
    expected = stride * metadata.height;
  let pixels: Buffer;
  try {
    pixels = inflateSync(Buffer.concat(compressed), { maxOutputLength: expected });
  } catch {
    return fail();
  }
  if (pixels.length !== expected) fail();
  for (let row = 0; row < metadata.height; row++)
    if ((pixels[row * stride] ?? 5) > 4) fail();
}

/** 先验证并上传不可变字节，再允许发布器提交引用它们的题目。 */
export async function uploadLearningImages(
  assets: readonly (PreparedLearningImage | DeferredLearningImage)[],
  store: LearningImageObjectStore,
): Promise<void> {
  for (const asset of assets) {
    globalThis.gc?.();
    const { metadata } = asset;
    const bytes = "bytes" in asset ? asset.bytes : await asset.loadBytes();
    verifyLearningImage(metadata, bytes);
    const key = learningImageObjectKey(metadata.id),
      checksum = Buffer.from(metadata.sha256, "hex").toString("base64");
    let remote = await store.headObject(key);
    if (!remote) {
      const upload = await store.createUploadUrl(
        {
          objectKey: key,
          byteSize: bytes.length,
          checksumSha256: checksum,
          contentType: metadata.contentType,
        },
        120,
      );
      const response = await fetch(upload.url, {
        method: "PUT",
        headers: upload.headers,
        body: Readable.from([bytes]),
        duplex: "half",
        signal: AbortSignal.timeout(30_000),
      });
      if (!response.ok)
        throw new AppError({
          code: "LEARNING_IMAGE_UPLOAD_FAILED",
          message: "图片素材上传失败，题库尚未发布。",
          statusCode: 503,
        });
      remote = await store.headObject(key);
    }
    if (
      remote?.byteSize !== metadata.byteSize ||
      remote.checksumSha256 !== checksum ||
      remote.contentType !== metadata.contentType
    )
      throw new Error(`图片资源 ${metadata.id} 的远端内容校验失败。`);
  }
}
