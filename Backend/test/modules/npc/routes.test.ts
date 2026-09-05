import { describe, expect, it, vi } from "vitest";
import { buildApp } from "../../../src/app.js";
import { loadConfig } from "../../../src/config/env.js";
import type { AuthService } from "../../../src/modules/auth/service.js";
import { registerNpcRoutes } from "../../../src/modules/npc/routes.js";
import type { NpcService } from "../../../src/modules/npc/service.js";
import { travelerIdCheckDigit } from "../../../src/modules/npc/traveler-id.js";
import { npcCard } from "../../helpers/npc-avatars.js";

describe("NPC avatar account scoping", () => {
  it("requires authentication for lookup and never caches one user's projection publicly", async () => {
    const userId = "00000000-0000-4000-8000-000000000001";
    const body = "1234567890";
    const travelerId = `${body}${String(travelerIdCheckDigit(body))}`;
    const find = vi.fn<NpcService["find"]>(() =>
      Promise.resolve({
        avatar: null,
        card: npcCard,
        id: userId,
        createdAt: new Date(0).toISOString(),
        travelerId,
      }),
    );
    const auth = {
      authenticate: () =>
        Promise.resolve({ userId, sessionId: userId, tokenVersion: 0 }),
    } as unknown as AuthService;
    const service = {
      find,
      link: vi.fn<NpcService["link"]>(),
      register: vi.fn<NpcService["register"]>(),
    } satisfies NpcService;
    const app = await buildApp(loadConfig({ NODE_ENV: "test" }), { logger: false });
    registerNpcRoutes(app, auth, service);
    try {
      const url = `/v1/npcs/by-traveler-id/${travelerId}`;
      const anonymous = await app.inject({ method: "GET", url });
      expect(anonymous.statusCode).toBe(401);
      expect(find).not.toHaveBeenCalled();
      const result = await app.inject({
        method: "GET",
        url,
        headers: { authorization: "Bearer test" },
      });
      expect(result.statusCode).toBe(200);
      expect(result.headers["cache-control"]).toBe("no-store");
      expect(find).toHaveBeenCalledWith(userId, travelerId);
    } finally {
      await app.close();
    }
  });
});
