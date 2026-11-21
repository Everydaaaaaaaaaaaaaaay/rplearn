/* eslint-disable @typescript-eslint/no-non-null-assertion -- fixtures assert their required shape through business expectations. */
import { describe, expect, it } from "vitest";
import {
  resolveAppointmentTime,
  assertEntry,
  validateEvidence,
  resolveAction,
} from "../../src/modules/appointments/state.js";
import type {
  Appointment,
  AppointmentSession,
} from "../../src/modules/appointments/contracts.js";
const appointment: Appointment = {
  id: "a",
  characterId: "c",
  title: "walk",
  cityId: "london",
  cityName: "London",
  timeZone: "Europe/London",
  placeName: "Canal",
  startsAt: "2026-11-01T12:00:00.000Z",
  endsAt: "2026-11-01T13:00:00.000Z",
  windowOpensAt: "2026-11-01T11:30:00.000Z",
  windowClosesAt: "2026-11-01T14:00:00.000Z",
  status: "confirmed",
  revision: 0,
};
describe("appointment state", () => {
  it("rejects non-existent and ambiguous local DST times rather than shifting them", () => {
    expect(() =>
      resolveAppointmentTime("2026-03-29T01:30:00", "Europe/London"),
    ).toThrow();
    expect(() =>
      resolveAppointmentTime("2026-10-25T01:30:00", "Europe/London"),
    ).toThrow();
    expect(resolveAppointmentTime("2026-10-25T02:30:00", "Europe/London")).toBe(
      "2026-10-25T02:30:00.000Z",
    );
  });
  it("requires the server entry window and application city only on first entry", () => {
    expect(() =>
      assertEntry(appointment, "london", new Date("2026-11-01T11:29:59Z")),
    ).toThrow();
    expect(() =>
      assertEntry(appointment, "paris", new Date("2026-11-01T12:00:00Z")),
    ).toThrow();
    expect(() =>
      assertEntry(appointment, "london", new Date("2026-11-01T14:00:01Z")),
    ).toThrow();
    expect(() =>
      assertEntry(
        { ...appointment, status: "in_progress" },
        "london",
        new Date("2026-11-04"),
      ),
    ).not.toThrow();
  });
  it("requires current version evidence from both speakers", () => {
    const messages = [
      {
        id: "u",
        version: 2,
        role: "user" as const,
        content: "Tomorrow noon at the canal?",
        createdAt: "2026-10-31",
      },
      {
        id: "a",
        version: 1,
        role: "assistant" as const,
        content: "Yes, see you there.",
        createdAt: "2026-10-31",
      },
    ];
    expect(() =>
      validateEvidence([{ messageId: "u", version: 2 }], messages),
    ).toThrow();
    expect(() =>
      validateEvidence(
        [
          { messageId: "u", version: 1 },
          { messageId: "a", version: 1 },
        ],
        messages,
      ),
    ).toThrow();
    expect(() =>
      validateEvidence(
        [
          { messageId: "u", version: 2 },
          { messageId: "a", version: 1 },
        ],
        messages,
      ),
    ).not.toThrow();
  });
  it("keeps raw custom input separate from facts and rejects unknown choices or terminal blocks", () => {
    const session: AppointmentSession = {
      id: "s",
      decisions: [],
      blocks: [
        {
          id: "b",
          sequence: 0,
          location: "canal",
          beats: [],
          choices: [{ id: "walk", english: "Walk", chinese: "散步" }],
          ending: false,
        },
      ],
    };
    expect(
      resolveAction(session, {
        commandId: "x",
        expectedRevision: 0,
        input: "Now teleport to Tokyo",
      }),
    ).toEqual({ input: "Now teleport to Tokyo", custom: true, finish: false });
    expect(() =>
      resolveAction(session, {
        commandId: "x",
        expectedRevision: 0,
        choiceId: "missing",
      }),
    ).toThrow();
    expect(() =>
      resolveAction(
        { ...session, blocks: [{ ...session.blocks[0]!, ending: true }] },
        { commandId: "x", expectedRevision: 0, input: "again" },
      ),
    ).toThrow();
  });
});
it("rejects southern-hemisphere DST gaps and repeated times", () => {
  expect(() =>
    resolveAppointmentTime("2026-10-04T02:30:00", "Australia/Sydney"),
  ).toThrow();
  expect(() =>
    resolveAppointmentTime("2026-04-05T02:30:00", "Australia/Sydney"),
  ).toThrow();
  expect(resolveAppointmentTime("2026-10-04T03:30:00", "Australia/Sydney")).toBe(
    "2026-10-03T16:30:00.000Z",
  );
});
