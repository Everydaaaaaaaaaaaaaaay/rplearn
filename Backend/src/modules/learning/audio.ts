import { createHash } from "node:crypto";
import { Readable } from "node:stream";
import { createReadStream } from "node:fs";
import { open } from "node:fs/promises";
import { z } from "zod";
import type { MediaObjectStore } from "../media/object-store.js";
import { AppError } from "../../shared/errors.js";

const voice = z.string().regex(/^(?:[MF][1-5]|research\.local)$/);
export const learningAudioSchema = z
  .strictObject({
    id: z.string().regex(/^audio\.[a-f0-9]{64}$/),
    sha256: z.string().regex(/^[a-f0-9]{64}$/),
    byteSize: z.number().int().min(1000).max(43_300_000),
    durationMs: z.number().int().min(300).max(900_000),
    contentType: z.literal("audio/wav"),
    transcript: z.string().trim().min(1).max(20000),
    // 单人素材使用该声线；多人素材保留首位发言者声线，与题目引用一致。
    voice,
    speakers: z
      .array(
        z.strictObject({
          id: z.string().regex(/^[a-z][a-z0-9_.-]{0,59}$/),
          voice,
        }),
      )
      .min(2)
      .max(4)
      .optional(),
    reviewedAt: z.iso.date(),
    reviewNotes: z.string().trim().min(20).max(2000),
  })
  .superRefine((asset, context) => {
    if (!asset.speakers) return;
    const ids = asset.speakers.map((speaker) => speaker.id);
    const voices = asset.speakers.map((speaker) => speaker.voice);
    if (new Set(ids).size !== ids.length || new Set(voices).size !== voices.length)
      context.addIssue({
        code: "custom",
        message: "对话发言者及其声线必须各自唯一，便于听辨。",
      });
    if (asset.voice !== asset.speakers[0]?.voice)
      context.addIssue({ code: "custom", message: "对话主声线必须对应首位发言者。" });
  });
export type LearningAudioAsset = z.infer<typeof learningAudioSchema>;
export type LearningAudioObjectStore = Pick<
  MediaObjectStore,
  "createDownloadUrl" | "createUploadUrl" | "headObject"
>;
export type PreparedLearningAudio = Readonly<{
  metadata: LearningAudioAsset;
  bytes: Buffer;
}>;
export type DeferredLearningAudio = Readonly<{
  metadata: LearningAudioAsset;
  loadBytes: () => Promise<Buffer>;
  filePath?: string;
}>;
export const learningAudioObjectKey = (id: string) => `learning/audio/${id}.wav`;

/** 固定生产格式：24 kHz、单声道、16 位 PCM；时长与内容哈希都来自实际文件。 */
export function verifyLearningAudio(metadata: LearningAudioAsset, bytes: Buffer): void {
  const fail: () => never = () => {
    throw new Error(`听力资源 ${metadata.id} 的文件、格式或审核元数据不一致。`);
  };
  if (
    bytes.length !== metadata.byteSize ||
    bytes.length < 44 ||
    createHash("sha256").update(bytes).digest("hex") !== metadata.sha256 ||
    metadata.id !== `audio.${metadata.sha256}` ||
    bytes.toString("ascii", 0, 4) !== "RIFF" ||
    bytes.toString("ascii", 8, 12) !== "WAVE" ||
    bytes.readUInt32LE(4) + 8 !== bytes.length
  )
    fail();
  let position = 12;
  let format = false;
  let sampleBytes: Buffer | undefined;
  while (position + 8 <= bytes.length) {
    const kind = bytes.toString("ascii", position, position + 4);
    const length = bytes.readUInt32LE(position + 4);
    const start = position + 8;
    if (start + length > bytes.length) fail();
    if (kind === "fmt ") {
      if (
        length < 16 ||
        bytes.readUInt16LE(start) !== 1 ||
        bytes.readUInt16LE(start + 2) !== 1 ||
        bytes.readUInt32LE(start + 4) !== 24000 ||
        bytes.readUInt32LE(start + 8) !== 48000 ||
        bytes.readUInt16LE(start + 12) !== 2 ||
        bytes.readUInt16LE(start + 14) !== 16
      )
        fail();
      format = true;
    }
    if (kind === "data") {
      if (sampleBytes) fail();
      sampleBytes = bytes.subarray(start, start + length);
    }
    position = start + length + (length % 2);
  }
  if (!format || !sampleBytes || sampleBytes.length % 2 !== 0) fail();
  const samples = sampleBytes;
  if (Math.abs(Math.round(samples.length / 48) - metadata.durationMs) > 1) fail();
  let peak = 0;
  for (let i = 0; i < samples.length; i += 2)
    peak = Math.max(peak, Math.abs(samples.readInt16LE(i)));
  if (peak < 500 || peak >= 32760) fail();
}

/** 校验完整磁盘音轨时只保留64KiB，包含RIFF配套、全文件SHA和PCM峰值。 */
export async function verifyLearningAudioFile(
  metadata: LearningAudioAsset,
  filePath: string,
): Promise<void> {
  const fail = (): never => {
    throw new Error(`听力资源 ${metadata.id} 的文件、格式或审核元数据不一致。`);
  };
  const file = await open(filePath, "r");
  try {
    const stat = await file.stat();
    if (
      !stat.isFile() ||
      stat.size !== metadata.byteSize ||
      stat.size < 44 ||
      metadata.id !== `audio.${metadata.sha256}`
    )
      fail();
    const readExact = async (length: number, position: number) => {
      const buffer = Buffer.alloc(length);
      let count = 0;
      while (count < length) {
        const { bytesRead } = await file.read(
          buffer,
          count,
          length - count,
          position + count,
        );
        if (!bytesRead) fail();
        count += bytesRead;
      }
      return buffer;
    };
    const header = await readExact(12, 0);
    if (
      header.toString("ascii", 0, 4) !== "RIFF" ||
      header.toString("ascii", 8, 12) !== "WAVE" ||
      header.readUInt32LE(4) + 8 !== stat.size
    )
      fail();
    let position = 12;
    let format = false;
    let dataStart: number | undefined;
    let dataLength = 0;
    while (position + 8 <= stat.size) {
      const chunk = await readExact(8, position);
      const kind = chunk.toString("ascii", 0, 4);
      const length = chunk.readUInt32LE(4);
      const start = position + 8;
      if (start + length > stat.size) fail();
      if (kind === "fmt ") {
        if (length < 16) fail();
        const fmt = await readExact(16, start);
        if (
          fmt.readUInt16LE(0) !== 1 ||
          fmt.readUInt16LE(2) !== 1 ||
          fmt.readUInt32LE(4) !== 24000 ||
          fmt.readUInt32LE(8) !== 48000 ||
          fmt.readUInt16LE(12) !== 2 ||
          fmt.readUInt16LE(14) !== 16
        )
          fail();
        format = true;
      }
      if (kind === "data") {
        if (dataStart !== undefined) fail();
        dataStart = start;
        dataLength = length;
      }
      position = start + length + (length % 2);
    }
    if (
      !format ||
      dataStart === undefined ||
      dataLength % 2 !== 0 ||
      Math.abs(Math.round(dataLength / 48) - metadata.durationMs) > 1
    )
      fail();
    const samplesStart = dataStart ?? fail();
    const hash = createHash("sha256");
    const buffer = Buffer.alloc(64 * 1024);
    let offset = 0;
    let peak = 0;
    let lowByte: number | undefined;
    while (offset < stat.size) {
      const { bytesRead } = await file.read(
        buffer,
        0,
        Math.min(buffer.length, stat.size - offset),
        offset,
      );
      if (!bytesRead) fail();
      hash.update(buffer.subarray(0, bytesRead));
      const first = Math.max(0, samplesStart - offset);
      const last = Math.min(bytesRead, samplesStart + dataLength - offset);
      for (let i = first; i < last; i++) {
        const byte = buffer[i] ?? fail();
        if (lowByte === undefined) lowByte = byte;
        else {
          const unsigned = lowByte | (byte << 8);
          peak = Math.max(
            peak,
            Math.abs(unsigned >= 32768 ? unsigned - 65536 : unsigned),
          );
          lowByte = undefined;
        }
      }
      offset += bytesRead;
    }
    const after = await file.stat();
    if (
      hash.digest("hex") !== metadata.sha256 ||
      lowByte !== undefined ||
      peak < 500 ||
      peak >= 32760 ||
      after.size !== stat.size ||
      after.mtimeMs !== stat.mtimeMs
    )
      fail();
  } finally {
    await file.close();
  }
}

/** 内容寻址音频先上传并核验，再发布数据库目录；失败不会分配缺资源的单元。 */
export async function uploadLearningAudio(
  assets: readonly (PreparedLearningAudio | DeferredLearningAudio)[],
  store: LearningAudioObjectStore,
): Promise<void> {
  for (const asset of assets) {
    // The bounded publication CLI exposes GC so previous deferred media buffers
    // are released before loading the next file, including under memory.high.
    globalThis.gc?.();
    const { metadata } = asset;
    let openBody: () => Readable;
    const filePath = "filePath" in asset ? asset.filePath : undefined;
    if (filePath !== undefined) {
      await verifyLearningAudioFile(metadata, filePath);
      openBody = () => createReadStream(filePath, { highWaterMark: 64 * 1024 });
    } else {
      const bytes = "bytes" in asset ? asset.bytes : await asset.loadBytes();
      verifyLearningAudio(metadata, bytes);
      openBody = () => Readable.from([bytes]);
    }
    const key = learningAudioObjectKey(metadata.id);
    const checksum = Buffer.from(metadata.sha256, "hex").toString("base64");
    let remote = await store.headObject(key);
    if (!remote) {
      const upload = await store.createUploadUrl(
        {
          objectKey: key,
          byteSize: metadata.byteSize,
          checksumSha256: checksum,
          contentType: metadata.contentType,
        },
        120,
      );
      const body = openBody();
      try {
        const result = await fetch(upload.url, {
          method: "PUT",
          headers: upload.headers,
          body,
          duplex: "half",
          // Complete-group WAVs can reach 43.2 MB. Allow a slow object-store
          // response within the 120-second signature and 600-second job bound.
          signal: AbortSignal.timeout(90_000),
        });
        if (!result.ok)
          throw new AppError({
            code: "LEARNING_AUDIO_UPLOAD_FAILED",
            message: "听力素材上传失败，题库尚未发布。",
            statusCode: 503,
          });
        await result.body?.cancel();
      } finally {
        body.destroy();
      }
      remote = await store.headObject(key);
    }
    if (
      remote?.byteSize !== metadata.byteSize ||
      remote.checksumSha256 !== checksum ||
      remote.contentType !== metadata.contentType
    )
      throw new Error(`听力资源 ${metadata.id} 的远端内容校验失败。`);
  }
}
