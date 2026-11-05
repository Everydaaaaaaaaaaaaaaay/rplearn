import type { DatabaseResource } from "../../db/client.js";
import type { ChatContentAccess, ChatProcessorOptions } from "./contracts.js";
import { ChatRepository } from "./repository.js";

export function createChatService(
  database: DatabaseResource,
  content: ChatContentAccess,
  options: ChatProcessorOptions,
) {
  const repository = new ChatRepository(
    database,
    content,
    options.coalesceMilliseconds ?? 450,
    options.leaseMilliseconds ?? 180_000,
  );
  return {
    open: repository.open.bind(repository),
    state: repository.state.bind(repository),
    retry: async (userId: string, conversationId: string, commandId: string) => {
      const state = await repository.state(userId, conversationId);
      if (state.generation?.status === "uncertain") {
        const claim = await repository.reclaim(
          userId,
          conversationId,
          state.generation.id,
        );
        if (claim) {
          const result = await options.recover?.(claim.input);
          if (result) {
            await repository.finish(claim, result.content);
            return repository.state(userId, conversationId);
          }
          await repository.uncertain(claim);
        }
      }
      return repository.retry(userId, conversationId, commandId);
    },
    observe: repository.observe.bind(repository),
    beforeCommand: repository.beforeCommand.bind(repository),
    assertLegacyAllowed: repository.assertLegacyAllowed.bind(repository),
    processNext: async (): Promise<boolean> => {
      const claim = await repository.claim();
      if (!claim) return false;
      if (claim.recoverOnly) {
        const result = await options.recover?.(claim.input);
        if (result) await repository.finish(claim, result.content);
        else await repository.uncertain(claim);
        return true;
      }
      let partial = "";
      const heartbeat = setInterval(() => {
        void repository.partial(claim, partial).catch(() => undefined);
      }, 15_000);
      try {
        const text = (
          await options.generate(claim.input, async (value) => {
            partial = value;
            await repository.partial(claim, value);
          })
        ).trim();
        if (!text) throw new Error("EmptyChatReply");
        await repository.finish(claim, text);
      } catch {
        const result = await options.recover?.(claim.input);
        if (result) await repository.finish(claim, result.content);
        else if (
          await options.operationPending?.(claim.input.userId, claim.input.generationId)
        )
          await repository.uncertain(claim);
        else await repository.fail(claim);
      } finally {
        clearInterval(heartbeat);
      }
      return true;
    },
  };
}
export type ChatService = ReturnType<typeof createChatService>;

export const sharedChatCoverage = ChatRepository.sharedCoverage.bind(ChatRepository);
