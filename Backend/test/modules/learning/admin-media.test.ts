import { describe, expect, it, vi } from "vitest";
import { readAdminLearningMedia } from "../../../src/modules/learning/admin-media.js";
import { learningAudioFixture } from "../../helpers/learning-audio.js";
import { learningImageFixture } from "../../helpers/learning-images.js";

const store = {
  createDownloadUrl: vi.fn(() =>
    Promise.resolve("https://assets.example.com/file?signature=private"),
  ),
};
describe("后台素材同源读取", () => {
  it("只从内容寻址存储下载，完整校验后返回音频与图片，不传管理员凭据", async () => {
    for (const asset of [learningAudioFixture(), learningImageFixture()]) {
      const download = vi.fn<typeof fetch>().mockResolvedValue(
        new Response(new Uint8Array(asset.bytes), {
          headers: {
            "content-type": asset.metadata.contentType,
            "content-length": String(asset.bytes.length),
          },
        }),
      );
      expect(await readAdminLearningMedia(asset.metadata, store, download)).toEqual(
        asset.bytes,
      );
      const init = download.mock.calls[0]?.[1];
      expect(init).toMatchObject({ redirect: "error", credentials: "omit" });
      expect(init?.headers).toBeUndefined();
    }
  });
  it("拒绝损坏文件、错误类型、截断与过长流，错误不泄露签名地址", async () => {
    const asset = learningAudioFixture();
    const corrupted = Buffer.from(asset.bytes);
    corrupted[60] = 1;
    const cases = [
      new Response(new Uint8Array(corrupted), {
        headers: { "content-type": "audio/wav" },
      }),
      new Response(new Uint8Array(asset.bytes), {
        headers: { "content-type": "text/html" },
      }),
      new Response(new Uint8Array(asset.bytes.subarray(0, 100)), {
        headers: { "content-type": "audio/wav" },
      }),
      new Response(
        new ReadableStream({
          start(controller) {
            controller.enqueue(new Uint8Array(asset.bytes));
            controller.enqueue(new Uint8Array(1));
          },
        }),
        { headers: { "content-type": "audio/wav" } },
      ),
    ];
    for (const response of cases) {
      await expect(
        readAdminLearningMedia(
          asset.metadata,
          store,
          vi.fn<typeof fetch>().mockResolvedValue(response),
        ),
      ).rejects.toMatchObject({
        code: "LEARNING_MEDIA_READ_FAILED",
        statusCode: 502,
        cause: undefined,
      });
    }
    await expect(
      readAdminLearningMedia(
        asset.metadata,
        store,
        vi
          .fn<typeof fetch>()
          .mockRejectedValue(new Error("https://secret.example?signature=private")),
      ),
    ).rejects.toThrow("素材暂时无法读取");
    await expect(
      readAdminLearningMedia(asset.metadata, undefined),
    ).rejects.toMatchObject({ statusCode: 503 });
    const download = vi.fn<typeof fetch>();
    await expect(
      readAdminLearningMedia(
        asset.metadata,
        { createDownloadUrl: () => Promise.resolve("http://untrusted.example/image") },
        download,
      ),
    ).rejects.toMatchObject({ statusCode: 502 });
    expect(download).not.toHaveBeenCalled();
  });
});
