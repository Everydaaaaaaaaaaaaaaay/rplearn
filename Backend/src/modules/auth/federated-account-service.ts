import type { DatabaseResource } from "../../db/client.js";
import { AuthRepository } from "./repository.js";
import type {
  FederatedAccount,
  VerifiedFederatedIdentity,
} from "./repository-types.js";

export type FederatedLinkResult =
  Readonly<{ identityId: string; status: "linked" }> | Readonly<{ status: "conflict" }>;

/** 外部提供方只负责验明身份；账号创建、查找与绑定统一在这里决定。 */
export type FederatedAccountService = Readonly<{
  findOrCreate: (identity: VerifiedFederatedIdentity) => Promise<FederatedAccount>;
  link: (
    userId: string,
    identity: VerifiedFederatedIdentity,
  ) => Promise<FederatedLinkResult>;
}>;

export function createFederatedAccountService(
  database: DatabaseResource,
): FederatedAccountService {
  const repository = new AuthRepository(database);
  return {
    findOrCreate: (identity) => repository.findOrCreateFederatedAccount(identity),
    link: (userId, identity) =>
      repository.linkFederatedIdentity({ ...identity, userId }),
  };
}
