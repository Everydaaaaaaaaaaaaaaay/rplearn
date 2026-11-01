/* eslint-disable @typescript-eslint/require-await -- async route doubles return fixed wire payloads. */
import Fastify from "fastify";
import { expect, it, vi } from "vitest";
import { registerAppointmentRoutes } from "../../src/modules/appointments/routes.js";
import type { AuthService } from "../../src/modules/auth/service.js";
import { setTimeout as delay } from "node:timers/promises";
it("lets authenticated generation outlast the normal socket timeout without extending other routes", async () => {
  const app = Fastify({ connectionTimeout: 100 });
  const id = "019c0123-4567-789a-8bcd-ef01234567f0";
  const slow = async () => { await delay(250); return { ok: true }; };
  registerAppointmentRoutes(app, { authenticate: async () => ({ userId: id, isGuest: false }) } as unknown as AuthService,
    { start: slow } as unknown as Parameters<typeof registerAppointmentRoutes>[2]);
  app.get("/normal", slow);
  try {
    const origin = await app.listen({ port: 0, host: "127.0.0.1" });
    const response = await fetch(`${origin}/v1/appointments/${id}/start`, {
      method: "POST", headers: { authorization: "Bearer test", "content-type": "application/json" },
      body: JSON.stringify({ commandId: id, expectedRevision: 0 }),
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
    await expect(fetch(`${origin}/normal`)).rejects.toThrow();
  } finally { await app.close(); }
});
it("authenticates all reads and mutations, rejects malformed commands and keeps city authoritative", async () => {
  const app = Fastify(),
    id = "019c0123-4567-789a-8bcd-ef01234567f0",
    commandId = "019c0123-4567-789a-8bcd-ef01234567f1";
  const authenticate = vi.fn(async () => ({ userId: id, isGuest: false }));
  const service = {
    list: vi.fn(async () => ({ appointments: [], serverNow: "2026-11-01T12:00:00Z" })),
    detect: vi.fn(),
    detail: vi.fn(),
    start: vi.fn(async () => ({ ok: true })),
    choose: vi.fn(),
    cancel: vi.fn(),
    settlementSeed: vi.fn(),
    settle: vi.fn(),
  };
  registerAppointmentRoutes(
    app,
    { authenticate } as unknown as AuthService,
    service as unknown as Parameters<typeof registerAppointmentRoutes>[2],
  );
  expect((await app.inject({ url: "/v1/appointments" })).statusCode).toBe(401);
  const headers = { authorization: "Bearer test-only-token" };
  expect((await app.inject({ url: "/v1/appointments", headers })).statusCode).toBe(200);
  expect(
    (
      await app.inject({
        method: "POST",
        url: `/v1/appointments/${id}/start`,
        headers,
        payload: { commandId, expectedRevision: 0, cityId: "london" },
      })
    ).statusCode,
  ).toBe(400);
  expect(service.start).not.toHaveBeenCalled();
  expect(
    (
      await app.inject({
        method: "POST",
        url: `/v1/appointments/${id}/start`,
        headers,
        payload: { commandId, expectedRevision: 0 },
      })
    ).statusCode,
  ).toBe(200);
  expect(service.start).toHaveBeenCalledWith(id, id, {
    commandId,
    expectedRevision: 0,
  });
  expect(
    (
      await app.inject({
        method: "POST",
        url: `/v1/appointments/${id}/settle`,
        headers,
        payload: {
          commandId,
          expectedCharacterVersion: 1,
          relationship: { affinity: 150 },
        },
      })
    ).statusCode,
  ).toBe(400);
  expect(service.settle).not.toHaveBeenCalled();
  await app.close();
});
it("requires a signed-in account for every appointment endpoint before reading or creating guest history", async () => {
  const app = Fastify(),
    id = "019c0123-4567-789a-8bcd-ef01234567f0";
  const service = {
    list: vi.fn(),
    detect: vi.fn(),
    detail: vi.fn(),
    start: vi.fn(),
    choose: vi.fn(),
    cancel: vi.fn(),
    settlementSeed: vi.fn(),
    settle: vi.fn(),
  };
  registerAppointmentRoutes(
    app,
    {
      authenticate: async () => ({ userId: id, isGuest: true }),
    } as unknown as AuthService,
    service,
  );
  for (const endpoint of [
    { method: "GET" as const, path: "" },
    { method: "GET" as const, path: `/${id}` },
    { method: "GET" as const, path: `/${id}/settlement` },
    ...["detect", `${id}/start`, `${id}/choices`, `${id}/cancel`, `${id}/settle`].map(
      (path) => ({ method: "POST" as const, path: `/${path}` }),
    ),
  ]) {
    const response = await app.inject({
      method: endpoint.method,
      url: `/v1/appointments${endpoint.path}`,
      headers: { authorization: "Bearer guest-token" },
      ...(endpoint.method === "POST" ? { payload: {} } : {}),
    });
    expect(response.statusCode).toBe(403);
    expect(response.json()).toMatchObject({ code: "LOGIN_REQUIRED" });
  }
  for (const handler of Object.values(service)) expect(handler).not.toHaveBeenCalled();
  await app.close();
});
