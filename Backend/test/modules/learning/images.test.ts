import { createHash } from "node:crypto";
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  uploadLearningImages,
  verifyLearningImage,
  type LearningImageObjectStore,
} from "../../../src/modules/learning/images.js";
import { learningImageFixture, pngChunk } from "../../helpers/learning-images.js";

afterEach(() => vi.unstubAllGlobals());
describe("图片文件验收", () => {
  it("匹配摘要仍不能掩盖损坏的 PNG 结构、CRC 或扫描行", () => {
    const { metadata, bytes } = learningImageFixture();
    expect(() => verifyLearningImage(metadata, bytes)).not.toThrow();
    const damaged = Buffer.from(bytes);
    damaged[30] = 0;
    const variants = [
      damaged,
      bytes.subarray(0, -12),
      Buffer.concat([
        bytes.subarray(0, -12),
        pngChunk("acTL", Buffer.alloc(8)),
        bytes.subarray(-12),
      ]),
    ];
    for (const data of variants) {
      const hash = createHash("sha256").update(data).digest("hex");
      expect(() =>
        verifyLearningImage(
          { ...metadata, byteSize: data.length, id: `image.${hash}`, sha256: hash },
          data,
        ),
      ).toThrow();
    }
    const invalidFilter = learningImageFixture(100, 5);
    expect(() =>
      verifyLearningImage(invalidFilter.metadata, invalidFilter.bytes),
    ).toThrow();
    expect(() => verifyLearningImage({ ...metadata, width: 1024 }, bytes)).toThrow();
    expect(() =>
      verifyLearningImage({ ...metadata, id: `image.${"a".repeat(64)}` }, bytes),
    ).toThrow();
  });
  it("上传后校验远端大小、摘要和类型；已归档资源不重复上传", async () => {
    const asset = learningImageFixture();
    const remote = {
      byteSize: asset.bytes.length,
      checksumSha256: Buffer.from(asset.metadata.sha256, "hex").toString("base64"),
      contentType: "image/png",
    };
    const head = vi.fn().mockResolvedValueOnce(undefined).mockResolvedValue(remote);
    const store: LearningImageObjectStore = {
      headObject: head,
      createDownloadUrl: vi.fn(),
      createUploadUrl: vi
        .fn()
        .mockResolvedValue({
          url: "https://assets.example.com/upload",
          headers: { "content-type": "image/png" },
        }),
    };
    const upload = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", upload);
    await uploadLearningImages([asset], store);
    await uploadLearningImages([asset], store);
    expect(upload).toHaveBeenCalledTimes(1);
    head.mockResolvedValue({ ...remote, checksumSha256: "wrong" });
    await expect(uploadLearningImages([asset], store)).rejects.toThrow(
      "远端内容校验失败",
    );
  });
});
