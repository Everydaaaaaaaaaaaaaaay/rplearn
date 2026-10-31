import { expect, it } from "vitest";
import {
  appointmentCharacter,
  appointmentMessages,
  verifyAppointmentEvidence,
} from "../../src/modules/appointments/context.js";
import type { ContentRecord } from "../../src/modules/content/types.js";
const record = (
  id: string,
  payload: unknown,
  type: ContentRecord["resourceType"] = "character",
  parentId: string | null = null,
): ContentRecord => ({
  resourceId: id,
  resourceType: type,
  parentId,
  payload,
  version: 1,
  createdAt: "2026-11-01T12:00:00Z",
  updatedAt: "2026-11-01T12:00:00Z",
  deletedAt: null,
});
it("does not allow removed contacts into new appointments", () => {
  expect(() =>
    appointmentCharacter(
      record("c", {
        contactStatus: "removed",
        card: { name: "Oliver", regionId: "london" },
      }),
    ),
  ).toThrow();
});
it("rejects another character conversation and excludes deleted/interrupted/story messages", () => {
  const c = record("conversation", {}, "conversation", "character"),
    m = record(
      "m",
      {
        role: "assistant",
        kind: "text",
        text: "Yes",
        createdAt: "2026-11-01T12:00:00Z",
      },
      "message",
      "conversation",
    );
  expect(() => appointmentMessages(c, "other", [m])).toThrow();
  expect(
    appointmentMessages(c, "character", [
      { ...m, deletedAt: "2026-11-01T12:00:00Z" },
      { ...m, payload: { ...(m.payload as object), isInterrupted: true } },
      { ...m, payload: { ...(m.payload as object), kind: "storyLine" } },
    ]),
  ).toEqual([]);
});

it("retains confirmation across metadata-only revisions but rejects changes to message meaning or validity", () => {
  const payload = {
    text: "Noon?",
    role: "user",
    kind: "text",
    createdAt: "2026-11-01T12:00:00Z",
    isInterrupted: false,
  };
  const message = record("u", payload, "message", "conversation");
  const saved = {
    id: "u",
    version: 1,
    role: "user" as const,
    content: "Noon?",
    createdAt: payload.createdAt,
  };
  expect(() =>
    verifyAppointmentEvidence([message], "conversation", [saved]),
  ).not.toThrow();
  expect(() =>
    verifyAppointmentEvidence(
      [
        {
          ...message,
          version: 4,
          payload: {
            ...payload,
            keywordRangesJson: "[]",
            translationZh: "中午？",
            coachReviewJson: "{}",
          },
        },
      ],
      "conversation",
      [saved],
    ),
  ).not.toThrow();
  for (const changed of [
    { ...message, version: 0 },
    { ...message, version: 2, payload: { ...payload, text: "Never mind" } },
    { ...message, version: 2, payload: { ...payload, role: "assistant" } },
    {
      ...message,
      version: 2,
      payload: { ...payload, createdAt: "2026-11-01T13:00:00Z" },
    },
    { ...message, version: 2, payload: { ...payload, isInterrupted: true } },
    { ...message, version: 2, payload: { ...payload, kind: "storyLine" } },
    { ...message, version: 2, deletedAt: "2026-11-01T12:30:00Z" },
    { ...message, parentId: "other" },
  ])
    expect(() =>
      verifyAppointmentEvidence([changed], "conversation", [saved]),
    ).toThrow();
});
it.each([
  ["capetown", "Africa/Johannesburg"],
  ["singapore", "Asia/Singapore"],
  ["dublin", "Europe/Dublin"],
  ["edinburgh", "Europe/London"],
  ["vancouver", "America/Vancouver"],
  ["auckland", "Pacific/Auckland"],
  ["nairobi", "Africa/Nairobi"],
  ["toronto", "America/Toronto"],
  ["sydney", "Australia/Sydney"],
  ["neworleans", "America/Chicago"],
  ["manchester", "Europe/London"],
  ["kingston", "America/Jamaica"],
])(
  "supports the active app city %s in its actual IANA timezone",
  (cityId, timeZone) => {
    expect(
      appointmentCharacter(
        record("c", { card: { name: "Companion", regionId: cityId } }),
      ),
    ).toMatchObject({ cityId, timeZone });
  },
);
