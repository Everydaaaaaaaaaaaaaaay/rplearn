import { createHash } from "node:crypto";
import { crc32, deflateSync } from "node:zlib";
import type { PreparedLearningImage } from "../../src/modules/learning/images.js";

export function pngChunk(kind: string, data: Buffer): Buffer {
  const head = Buffer.alloc(8);
  head.writeUInt32BE(data.length);
  head.write(kind, 4, "ascii");
  const checksum = Buffer.alloc(4);
  checksum.writeUInt32BE(crc32(Buffer.concat([head.subarray(4), data])));
  return Buffer.concat([head, data, checksum]);
}
/** 纯色工程样本，不得作为教学插图发布。 */
export function learningImageFixture(color = 100, filter = 0): PreparedLearningImage {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(128, 0);
  header.writeUInt32BE(128, 4);
  header[8] = 8;
  header[9] = 2;
  const pixels = Buffer.alloc(128 * 385, color);
  for (let row = 0; row < 128; row++) pixels[row * 385] = filter;
  const bytes = Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    pngChunk("IHDR", header),
    pngChunk("IDAT", deflateSync(pixels)),
    pngChunk("IEND", Buffer.alloc(0)),
  ]);
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  return {
    bytes,
    metadata: {
      id: `image.${sha256}`,
      sha256,
      byteSize: bytes.length,
      width: 128,
      height: 128,
      contentType: "image/png",
      description: "仅用于程序验收的纯色图片。",
      source: "测试代码生成的工程样本。",
      reviewedBy: "程序测试",
      reviewedAt: "2026-09-26",
      reviewNotes: "仅用于验证图片字节和授权访问，不是正式教学插图。",
    },
  };
}
