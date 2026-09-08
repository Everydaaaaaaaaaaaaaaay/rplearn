import { createHash } from "node:crypto";
import type { DatabaseResource } from "../../db/client.js";
import { NpcRepository } from "./repository.js";
import type {
  LinkNpcRelationshipInput,
  PublicNpc,
  RegisterPublicNpcInput,
  NpcEncounterContext,
  NpcEncounterSelection,
  NpcDiversityReview,
  ReviewNpcDiversityInput,
} from "./types.js";

export type NpcService = Readonly<{
  selectEncounter: (
    userId: string,
    context: NpcEncounterContext,
  ) => Promise<NpcEncounterSelection>;
  retryPendingAvatars: () => Promise<{ attempted: number; matched: number }>;
  reviewDiversity: (
    userId: string,
    input: ReviewNpcDiversityInput,
  ) => Promise<NpcDiversityReview>;
  find: (travelerId: string) => Promise<PublicNpc>;
  link: (
    userId: string,
    npcId: string,
    input: LinkNpcRelationshipInput,
  ) => Promise<void>;
  register: (userId: string, input: RegisterPublicNpcInput) => Promise<PublicNpc>;
}>;

export function createNpcService(
  database: DatabaseResource,
  draw?: (maximum: number) => number,
): NpcService {
  const repository = new NpcRepository(database, draw);
  return {
    selectEncounter: (userId, context) => repository.selectEncounter(userId, context),
    retryPendingAvatars: () => repository.retryPendingAvatars(),
    reviewDiversity: (userId, input) => repository.reviewDiversity(userId, input),
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
