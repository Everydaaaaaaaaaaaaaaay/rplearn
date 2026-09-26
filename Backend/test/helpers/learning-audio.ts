import { createHash } from "node:crypto";
import type { PreparedLearningAudio } from "../../src/modules/learning/audio.js";

/** 仅供音频合同/鉴权测试的正弦波，不能导入正式题库。 */
export function learningAudioFixture(
  transcript = "Water, please.",
  voice = "M5",
  frequency = 440,
): PreparedLearningAudio {
  const bytes = Buffer.alloc(44 + 48_000);
  bytes.write("RIFF", 0);
  bytes.writeUInt32LE(bytes.length - 8, 4);
  bytes.write("WAVEfmt ", 8);
  bytes.writeUInt32LE(16, 16);
  bytes.writeUInt16LE(1, 20);
  bytes.writeUInt16LE(1, 22);
  bytes.writeUInt32LE(24000, 24);
  bytes.writeUInt32LE(48000, 28);
  bytes.writeUInt16LE(2, 32);
  bytes.writeUInt16LE(16, 34);
  bytes.write("data", 36);
  bytes.writeUInt32LE(48000, 40);
  for (let i = 0; i < 24000; i++)
    bytes.writeInt16LE(
      Math.round(3000 * Math.sin((i * frequency * 2 * Math.PI) / 24000)),
      44 + i * 2,
    );
  const sha256 = createHash("sha256").update(bytes).digest("hex");
  return {
    bytes,
    metadata: {
      id: `audio.${sha256}`,
      sha256,
      byteSize: bytes.length,
      durationMs: 1000,
      contentType: "audio/wav",
      transcript,
      voice,
      reviewedAt: "2026-09-26",
      reviewNotes: "程序测试专用的正弦波，只检查工程合同，不能作为语音教学内容发布。",
    },
  };
}
