import { createHash } from "node:crypto";
import type { DatabaseResource } from "../../db/client.js";
import { NpcRepository } from "./repository.js";
import type {
  LinkNpcRelationshipInput,
  PublicNpc,
  RegisterPublicNpcInput,
} from "./types.js";

export type NpcService = Readonly<{
  retryPendingAvatars: () => Promise<{ attempted: number; matched: number }>;
  find: (travelerId: string) => Promise<PublicNpc>;
  link: (
    userId: string,
    npcId: string,
    input: LinkNpcRelationshipInput,
  ) => Promise<void>;
  register: (userId: string, input: RegisterPublicNpcInput) => Promise<PublicNpc>;
}>;

export function createNpcService(database: DatabaseResource): NpcService {
  const repository = new NpcRepository(database);
  return {
    retryPendingAvatars: () => repository.retryPendingAvatars(),
    find: (travelerId) => repository.find(travelerId),
    link: (userId, npcId, input) => repository.link(userId, npcId, input),
    register: (userId, input) => {
      const cardHash = createHash("sha256")
        .update(
          JSON.stringify(
            input.requiredAvatarTags?.length
              ? {
                  card: input.card,
                  requiredAvatarTags: [...new Set(input.requiredAvatarTags)].sort(),
                }
              : input.card,
          ),
        )
        .digest("hex");
      return repository.register(userId, input, cardHash);
    },
  };
}
