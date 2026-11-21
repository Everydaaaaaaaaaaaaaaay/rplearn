import { expect, it } from "vitest";
import { currentAppointmentMemory } from "../../src/modules/appointments/memory-state.js";
const original = {
  id: "memory",
  content: "Original shared experience",
  status: "active",
};
const memory = (metadata: unknown) => ({
  deletedAt: null,
  payload: { content: "@lingotrip-memory-v2:" + JSON.stringify(metadata) },
});
it("projects edited text and forgetting from managed memory metadata without mutating saved history", () => {
  expect(
    currentAppointmentMemory(
      original,
      memory({ text: "User's corrected experience", status: "active", edited: true }),
    ),
  ).toEqual({ ...original, content: "User's corrected experience", status: "edited" });
  expect(
    currentAppointmentMemory(
      original,
      memory({ text: "", status: "active", edited: true, forgotten: true }),
    ),
  ).toEqual({ ...original, content: "", status: "forgotten" });
  expect(original).toEqual({
    id: "memory",
    content: "Original shared experience",
    status: "active",
  });
});
it("distinguishes archived, deleted and unavailable memory management states", () => {
  expect(
    currentAppointmentMemory(original, memory({ text: "Experience", archived: true })),
  ).toMatchObject({ status: "archived" });
  expect(currentAppointmentMemory(original, undefined)).toEqual({
    ...original,
    content: "",
    status: "deleted",
  });
  expect(
    currentAppointmentMemory(original, {
      ...memory({ text: "Experience" }),
      deletedAt: "2026-11-01T00:00:00Z",
    }),
  ).toEqual({ ...original, content: "", status: "deleted" });
  expect(
    currentAppointmentMemory(original, {
      deletedAt: null,
      payload: { content: "@lingotrip-memory-v2:malformed" },
    }),
  ).toEqual({ ...original, content: "", status: "unavailable" });
});
