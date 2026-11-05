import type { AiService } from "../ai/service.js";
import type { ChatProcessorOptions } from "./contracts.js";

/** The conversation service supplies accepted history and a durable operation ID. */
export function createChatGeneration(ai: AiService): ChatProcessorOptions["generate"] {
  return async (input, onDelta) => {
    const stream = await ai.stream(input.userId, {
      task: "conversation",
      messages: input.messages,
      maxOutputTokens: 120,
      ...(input.voiceLeaseId === undefined ? {} : { voiceLeaseId: input.voiceLeaseId }),
      operationId: input.generationId,
      responseFormat: "text",
      ...(input.learningChat === undefined ? {} : { learningChat: input.learningChat }),
    });
    let partial = "";
    let lastCheckpoint = 0;
    for await (const event of stream.events) {
      if (event.type !== "delta") continue;
      partial += event.text;
      if (Date.now() - lastCheckpoint >= 250) {
        await onDelta(partial);
        lastCheckpoint = Date.now();
      }
    }
    await onDelta(partial);
    return partial;
  };
}
