import type { DatabaseResource } from "../../db/client.js";
import type { LearningContextReader } from "./context.js";
import { LearningChatRepository, type LearningChatReader } from "./chat-repository.js";

export function createLearningChatService(
  database: DatabaseResource,
  context: LearningContextReader,
  reader: LearningChatReader,
) {
  const repository = new LearningChatRepository(database, context, reader);
  return {
    enqueue: repository.enqueue.bind(repository),
    begin: repository.begin.bind(repository),
    complete: repository.complete.bind(repository),
    drain: repository.drain.bind(repository),
    processPending: async () => {
      const users = await repository.pendingUsers(20);
      let processed = 0;
      for (const user of users) processed += await repository.drain(user.user_id);
      return processed;
    },
  };
}
