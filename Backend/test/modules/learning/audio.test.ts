import { describe, expect, it, vi, afterEach } from "vitest";
import {
  uploadLearningAudio,
  verifyLearningAudio,
  type LearningAudioObjectStore,
} from "../../../src/modules/learning/audio.js";
import { learningAudioFixture } from "../../helpers/learning-audio.js";

afterEach(() => vi.unstubAllGlobals());
describe("听力资源完整性与发布顺序", () => {
  it("实际字节、时长和内容寻址必须同时一致", () => {
    const { metadata, bytes } = learningAudioFixture();
    expect(() => verifyLearningAudio(metadata, bytes)).not.toThrow();
    const damaged = Buffer.from(bytes);
    damaged[60] = 1;
    expect(() => verifyLearningAudio(metadata, damaged)).toThrow();
    expect(() =>
      verifyLearningAudio({ ...metadata, durationMs: 2000 }, bytes),
    ).toThrow();
    expect(() =>
      verifyLearningAudio({ ...metadata, id: `audio.${"a".repeat(64)}` }, bytes),
    ).toThrow();
  });
  it("上传后检查远端校验和；远端已有相同资源时不重传", async () => {
    const asset = learningAudioFixture();
    const remote = {
      byteSize: asset.bytes.length,
      checksumSha256: Buffer.from(asset.metadata.sha256, "hex").toString("base64"),
      contentType: "audio/wav",
    };
    const head = vi.fn().mockResolvedValueOnce(undefined).mockResolvedValue(remote);
    const store: LearningAudioObjectStore = {
      headObject: head,
      createDownloadUrl: vi.fn(),
      createUploadUrl: vi
        .fn()
        .mockResolvedValue({
          url: "https://assets.example.com/upload",
          headers: { "content-type": "audio/wav" },
        }),
    };
    const upload = vi.fn().mockResolvedValue({ ok: true });
    vi.stubGlobal("fetch", upload);
    await uploadLearningAudio([asset], store);
    await uploadLearningAudio([asset], store);
    expect(upload).toHaveBeenCalledTimes(1);
    head.mockResolvedValue({ ...remote, checksumSha256: "wrong" });
    await expect(uploadLearningAudio([asset], store)).rejects.toThrow(
      "远端内容校验失败",
    );
  });
});
