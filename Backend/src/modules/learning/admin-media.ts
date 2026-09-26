import { AppError } from "../../shared/errors.js";
import {
  learningAudioObjectKey,
  verifyLearningAudio,
  type LearningAudioAsset,
  type LearningAudioObjectStore,
} from "./audio.js";
import {
  learningImageObjectKey,
  verifyLearningImage,
  type LearningImageAsset,
} from "./images.js";

/** 后台同源代理，不把管理员凭据或存储签名交给图片、音频元素。 */
export async function readAdminLearningMedia(
  asset: LearningAudioAsset | LearningImageAsset,
  store: Pick<LearningAudioObjectStore, "createDownloadUrl"> | undefined,
  download: typeof fetch = fetch,
): Promise<Buffer> {
  if (!store)
    throw new AppError({
      code: "LEARNING_MEDIA_UNAVAILABLE",
      message: "素材存储尚未配置，请联系维护者。",
      statusCode: 503,
      expose: true,
    });
  try {
    const isImage = asset.contentType === "image/png";
    const key = isImage
      ? learningImageObjectKey(asset.id)
      : learningAudioObjectKey(asset.id);
    const url = new URL(await store.createDownloadUrl(key, 60));
    if (url.protocol !== "https:" || url.username || url.password)
      throw new Error("下载地址不可用。");
    const response = await download(url, {
      redirect: "error",
      credentials: "omit",
      signal: AbortSignal.timeout(15_000),
    });
    const length = response.headers.get("content-length");
    if (
      !response.ok ||
      !response.body ||
      response.headers.get("content-type")?.split(";")[0]?.trim() !==
        asset.contentType ||
      (length !== null && Number(length) !== asset.byteSize)
    ) {
      await response.body?.cancel();
      throw new Error("素材响应不符合登记信息。");
    }
    const reader = response.body.getReader();
    const chunks: Uint8Array[] = [];
    let total = 0;
    try {
      for (;;) {
        const result = await reader.read();
        if (result.done) break;
        const value: unknown = result.value;
        if (!(value instanceof Uint8Array)) throw new Error("素材流格式无效。");
        total += value.byteLength;
        if (total > asset.byteSize) throw new Error("素材超过登记大小。");
        chunks.push(value);
      }
    } finally {
      await reader.cancel();
      reader.releaseLock();
    }
    const bytes = Buffer.concat(chunks);
    if (asset.contentType === "image/png") verifyLearningImage(asset, bytes);
    else verifyLearningAudio(asset, bytes);
    return bytes;
  } catch {
    // 不传播包含签名下载地址的供应商错误；页面可明确重试。
    throw new AppError({
      code: "LEARNING_MEDIA_READ_FAILED",
      message: "素材暂时无法读取或校验未通过，请重试；持续失败时请联系维护者。",
      statusCode: 502,
      expose: true,
    });
  }
}
