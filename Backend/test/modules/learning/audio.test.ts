import { describe, expect, it, vi, afterEach } from "vitest";
import { createHash } from "node:crypto";
import { createServer } from "node:http";
import { mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  uploadLearningAudio,
  verifyLearningAudio,
  verifyLearningAudioFile,
  learningAudioSchema,
  type LearningAudioObjectStore,
} from "../../../src/modules/learning/audio.js";
import { learningAudioFixture } from "../../helpers/learning-audio.js";

afterEach(() => vi.unstubAllGlobals());
describe("听力资源完整性与发布顺序", () => {
  it("单人素材不增加默认字段；双人素材完整记录可辨声线和首位发言者", () => {
    const { metadata } = learningAudioFixture();
    expect(learningAudioSchema.parse(metadata)).toEqual(metadata);
    const dialogue = {
      ...metadata,
      voice: "F3",
      speakers: [
        { id: "a", voice: "F3" },
        { id: "b", voice: "M5" },
      ],
    };
    expect(learningAudioSchema.parse(dialogue)).toEqual(dialogue);
    for (const speakers of [
      [{ id: "a", voice: "F3" }],
      [
        { id: "a", voice: "F3" },
        { id: "a", voice: "M5" },
      ],
      [
        { id: "a", voice: "F3" },
        { id: "b", voice: "F3" },
      ],
      [
        { id: "a", voice: "F3" },
        { id: "b", voice: "unknown" },
      ],
      [
        { id: "a", voice: "M5" },
        { id: "b", voice: "F3" },
      ],
    ])
      expect(learningAudioSchema.safeParse({ ...dialogue, speakers }).success).toBe(
        false,
      );
  });
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
      createUploadUrl: vi.fn().mockResolvedValue({
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
  it("磁盘分块校验保留SHA、WAV格式、时长和峰值约束", async () => {
    const { metadata, bytes } = learningAudioFixture();
    const directory = await mkdtemp(join(tmpdir(), "learning-audio-file-"));
    const filePath = join(directory, "test.wav");
    const metadataFor = (body: Buffer) => {
      const sha256 = createHash("sha256").update(body).digest("hex");
      return { ...metadata, byteSize: body.length, sha256, id: `audio.${sha256}` };
    };
    try {
      await writeFile(filePath, bytes);
      await expect(
        verifyLearningAudioFile(metadata, filePath),
      ).resolves.toBeUndefined();
      await expect(
        verifyLearningAudioFile({ ...metadata, durationMs: 2000 }, filePath),
      ).rejects.toThrow();
      const changed = Buffer.from(bytes);
      changed[changed.length - 1] = changed.readUInt8(changed.length - 1) ^ 1;
      await writeFile(filePath, changed);
      await expect(verifyLearningAudioFile(metadata, filePath)).rejects.toThrow();
      const wrongFormat = Buffer.from(bytes);
      wrongFormat.writeUInt16LE(2, 22);
      await writeFile(filePath, wrongFormat);
      await expect(
        verifyLearningAudioFile(metadataFor(wrongFormat), filePath),
      ).rejects.toThrow();
      const silent = Buffer.from(bytes);
      silent.fill(0, 44);
      await writeFile(filePath, silent);
      await expect(
        verifyLearningAudioFile(metadataFor(silent), filePath),
      ).rejects.toThrow();
      const junk = Buffer.from([74, 85, 78, 75, 3, 0, 0, 0, 1, 2, 3, 0]);
      const withChunk = Buffer.concat([
        bytes.subarray(0, 36),
        junk,
        bytes.subarray(36),
      ]);
      withChunk.writeUInt32LE(withChunk.length - 8, 4);
      await writeFile(filePath, withChunk);
      expect(() =>
        verifyLearningAudio(metadataFor(withChunk), withChunk),
      ).not.toThrow();
      await expect(
        verifyLearningAudioFile(metadataFor(withChunk), filePath),
      ).resolves.toBeUndefined();
    } finally {
      await rm(directory, { recursive: true, force: true });
    }
  });
  it("最大磁盘音轨通过慢响应 HTTP 分块上传，字节和长度不丢失", async () => {
    const fixture = learningAudioFixture();
    const bytes = Buffer.alloc(44 + 48_000 * 900);
    bytes.fill(fixture.bytes.subarray(44), 44);
    fixture.bytes.copy(bytes, 0, 0, 44);
    bytes.writeUInt32LE(bytes.length - 8, 4);
    bytes.writeUInt32LE(bytes.length - 44, 40);
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    const directory = await mkdtemp(join(tmpdir(), "learning-audio-upload-"));
    const filePath = join(directory, "largest.wav");
    await writeFile(filePath, bytes);
    const asset = {
      filePath,
      loadBytes: () => Promise.reject(new Error("磁盘音轨不得整段载入Buffer")),
      metadata: {
        ...fixture.metadata,
        id: `audio.${sha256}`,
        sha256,
        byteSize: bytes.length,
        durationMs: 900_000,
      },
    };
    let received:
      { byteSize: number; checksumSha256: string; contentType: string } | undefined;
    let declaredLength: string | undefined;
    const server = createServer((request, response) => {
      const hash = createHash("sha256");
      let size = 0;
      declaredLength = request.headers["content-length"];
      request.on("data", (chunk: Buffer) => {
        size += chunk.length;
        hash.update(chunk);
      });
      request.on("end", () => {
        received = {
          byteSize: size,
          checksumSha256: hash.digest("base64"),
          contentType: request.headers["content-type"] ?? "",
        };
        // A complete WAV may take longer than the former short-clip timeout.
        setTimeout(() => response.writeHead(200).end(), 32_000);
      });
    });
    await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
    try {
      const address = server.address();
      if (!address || typeof address === "string")
        throw new Error("Missing test server address");
      const store: LearningAudioObjectStore = {
        headObject: () => Promise.resolve(received),
        createDownloadUrl: vi.fn(),
        createUploadUrl: () =>
          Promise.resolve({
            url: `http://127.0.0.1:${String(address.port)}/upload`,
            headers: {
              "content-type": "audio/wav",
              "content-length": String(bytes.length),
            },
          }),
      };
      await uploadLearningAudio([asset], store);
      expect(declaredLength).toBe(String(bytes.length));
      expect(received).toEqual({
        byteSize: bytes.length,
        checksumSha256: Buffer.from(sha256, "hex").toString("base64"),
        contentType: "audio/wav",
      });
    } finally {
      server.closeAllConnections();
      await new Promise<void>((resolve, reject) =>
        server.close((error) => (error ? reject(error) : resolve())),
      );
      await rm(directory, { recursive: true, force: true });
    }
  }, 45_000);
});
