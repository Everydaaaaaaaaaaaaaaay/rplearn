import { readFile } from "node:fs/promises";
import { z } from "zod";
import { questionAudios, type LearningQuestion } from "./content.js";

const segment = z.strictObject({
  text: z.string().trim().min(1).max(20000),
  pauseAfterMs: z.number().int().min(0).max(30000),
});
export const listeningScriptSchema = z.strictObject({
  assetId: z.string(),
  segments: z.array(segment).min(1).max(500),
});
const registrySchema = z.object({
  version: z.literal(1),
  assets: z.record(
    z.string(),
    z.object({ segments: z.array(segment).min(1).max(500) }),
  ),
});
let registry: Promise<z.infer<typeof registrySchema>> | undefined;
function scripts() {
  return (registry ??= readFile(
    new URL("../../../config/learning/listening-scripts.json", import.meta.url),
    "utf8",
  ).then((text) => registrySchema.parse(JSON.parse(text) as unknown)));
}

/** Only called after ownership and question/asset binding have been checked.
 * The script is not part of the visible question or feedback; PCM stays on device.
 */
export async function questionListeningScript(
  question: LearningQuestion,
  assetId: string,
) {
  const audio = questionAudios(question).find((item) => item.assetId === assetId);
  if (!audio) return undefined;
  const authored = (await scripts()).assets[assetId];
  if (authored) return { assetId, segments: authored.segments };
  const material = { text: audio.text, pauseAfterMs: 0 };
  const segments = [material];
  // Early picture tasks keep their short audio and age-appropriate instructions.
  // Only a real English question is appended; Chinese directions never enter TTS.
  if (
    question.type === "listeningChoice" &&
    question.prompt.includes("?") &&
    !/\p{Script=Han}/u.test(question.prompt)
  ) {
    material.pauseAfterMs = 3000;
    segments.push({ text: `Question: ${question.prompt}`, pauseAfterMs: 0 });
  }
  return listeningScriptSchema.parse({ assetId, segments });
}
