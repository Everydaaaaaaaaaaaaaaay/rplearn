import { createHash } from "node:crypto";
import { z } from "zod";
import type { MediaObjectStore } from "../media/object-store.js";
import { AppError } from "../../shared/errors.js";

const voice = z.string().regex(/^[MF][1-5]$/);
export const learningAudioSchema = z
  .strictObject({
    id: z.string().regex(/^audio\.[a-f0-9]{64}$/),
    sha256: z.string().regex(/^[a-f0-9]{64}$/),
    byteSize: z.number().int().min(1000).max(3_000_000),
    durationMs: z.number().int().min(300).max(60_000),
    contentType: z.literal("audio/wav"),
    transcript: z.string().trim().min(1).max(1200),
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

/** 内容寻址音频先上传并核验，再发布数据库目录；失败不会分配缺资源的单元。 */
export async function uploadLearningAudio(
  assets: readonly (PreparedLearningAudio | DeferredLearningAudio)[],
  store: LearningAudioObjectStore,
): Promise<void> {
  for (const asset of assets) {
    const { metadata } = asset;
    const bytes = "bytes" in asset ? asset.bytes : await asset.loadBytes();
    verifyLearningAudio(metadata, bytes);
    const key = learningAudioObjectKey(metadata.id);
    const checksum = Buffer.from(metadata.sha256, "hex").toString("base64");
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
      const result = await fetch(upload.url, {
        method: "PUT",
        headers: upload.headers,
        body: new Uint8Array(bytes),
        signal: AbortSignal.timeout(30_000),
      });
      if (!result.ok)
        throw new AppError({
          code: "LEARNING_AUDIO_UPLOAD_FAILED",
          message: "听力素材上传失败，题库尚未发布。",
          statusCode: 503,
        });
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
