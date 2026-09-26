import { createHash } from "node:crypto";
import { z } from "zod";

const uuid = z.uuid().transform((value) => value.toLowerCase());

/** 只关联服务端已签发周期，不接受字数或奖励值。普通同步不带此字段。 */
export const learningMessageOriginSchema = z.discriminatedUnion("source", [
  z.strictObject({ source: z.literal("user"), cycleId: uuid }),
  z
    .strictObject({
      source: z.literal("assistant"),
      cycleId: uuid,
      userMessageId: uuid,
      operationId: uuid,
      fragmentIndex: z.number().int().min(0).max(7),
      fragmentCount: z.number().int().min(1).max(8),
    })
    .refine((value) => value.fragmentIndex < value.fragmentCount),
]);
export const learningChatContextSchema = z.strictObject({
  conversationId: uuid,
  userMessageId: uuid,
  cycleId: uuid,
});
export type LearningMessageOrigin = z.infer<typeof learningMessageOriginSchema>;
export type LearningChatContext = z.infer<typeof learningChatContextSchema>;

/** 客户端分泡只改变空白；比较完整内容，不能凭局部子串申领一次回复。 */
export function chatBodyFingerprint(body: string): string {
  return createHash("sha256").update(body.replace(/\s/gu, "")).digest("hex");
}
