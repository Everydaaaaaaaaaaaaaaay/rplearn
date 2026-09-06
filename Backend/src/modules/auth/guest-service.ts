import { createHmac } from "node:crypto";
import type { RuntimeConfig } from "../../config/env.js";
import type { DatabaseResource } from "../../db/client.js";
import { GuestRepository } from "./guest-repository.js";
import type { AuthService } from "./service.js";
import type { AuthTokenPair, DeviceDescriptor, RequestMetadata } from "./types.js";

export type GuestService = Readonly<{
  session: (
    key: string,
    device: DeviceDescriptor,
    metadata: RequestMetadata,
  ) => Promise<AuthTokenPair>;
}>;

export function createGuestService(
  config: RuntimeConfig,
  database: DatabaseResource,
  auth: AuthService,
): GuestService {
  const repository = new GuestRepository(database);
  return {
    session: async (key, device, metadata) => {
      const hash = createHmac("sha256", config.authTokenHashPepper)
        .update(`guest-installation:${key}`)
        .digest("hex");
      const principal = await repository.resolve(hash);
      return auth.loginFederated(
        principal.userId,
        principal.tokenVersion,
        device,
        metadata,
      );
    },
  };
}
