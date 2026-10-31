import { z } from "zod";
import type { AppointmentCharacter, AppointmentMessage } from "./contracts.js";
import type { ContentRecord } from "../content/types.js";
import { appointmentError } from "./state.js";
const cities: Record<string, { name: string; zone: string }> = {
  london: { name: "伦敦", zone: "Europe/London" },
  melbourne: { name: "墨尔本", zone: "Australia/Melbourne" },
  newyork: { name: "纽约", zone: "America/New_York" },
  capetown: { name: "开普敦", zone: "Africa/Johannesburg" },
  singapore: { name: "新加坡", zone: "Asia/Singapore" },
  dublin: { name: "都柏林", zone: "Europe/Dublin" },
  edinburgh: { name: "爱丁堡", zone: "Europe/London" },
  vancouver: { name: "温哥华", zone: "America/Vancouver" },
  auckland: { name: "奥克兰", zone: "Pacific/Auckland" },
  nairobi: { name: "内罗毕", zone: "Africa/Nairobi" },
  toronto: { name: "多伦多", zone: "America/Toronto" },
  sydney: { name: "悉尼", zone: "Australia/Sydney" },
  neworleans: { name: "新奥尔良", zone: "America/Chicago" },
  manchester: { name: "曼彻斯特", zone: "Europe/London" },
  kingston: { name: "金斯敦", zone: "America/Jamaica" },
};
export function appointmentCharacter(
  record: ContentRecord | undefined,
): AppointmentCharacter {
  const parsed = z
    .object({
      contactStatus: z.string().optional(),
      card: z.object({ name: z.string(), regionId: z.string() }),
    })
    .safeParse(record?.payload);
  if (
    record?.deletedAt !== null ||
    !parsed.success ||
    parsed.data.contactStatus === "removed"
  )
    appointmentError("APPOINTMENT_CHARACTER_NOT_FOUND", "请先同步旅伴资料。", 404);
  const city = cities[parsed.data.card.regionId];
  if (!city)
    appointmentError("APPOINTMENT_CITY_UNAVAILABLE", "这个城市的赴约暂未开放。", 422);
  return {
    id: record.resourceId,
    name: parsed.data.card.name,
    cityId: parsed.data.card.regionId,
    cityName: city.name,
    timeZone: city.zone,
    persona: record.payload,
  };
}
export function appointmentMessages(
  conversation: ContentRecord | undefined,
  characterId: string,
  records: ContentRecord[],
): AppointmentMessage[] {
  if (
    conversation?.deletedAt !== null ||
    conversation.parentId?.toLowerCase() !== characterId.toLowerCase()
  )
    appointmentError(
      "APPOINTMENT_CONVERSATION_NOT_FOUND",
      "请先同步这位旅伴的对话。",
      404,
    );
  return records.flatMap((record) => {
    if (record.deletedAt !== null) return [];
    const parsed = z
      .object({
        role: z.enum(["user", "assistant"]),
        text: z.string().min(1),
        kind: z.enum(["text", "voice"]),
        isInterrupted: z.boolean().optional(),
        createdAt: z.string(),
      })
      .safeParse(record.payload);
    if (!parsed.success || parsed.data.isInterrupted) return [];
    return [
      {
        id: record.resourceId,
        version: record.version,
        role: parsed.data.role,
        content: parsed.data.text,
        createdAt: parsed.data.createdAt,
        serverCreatedAt: record.createdAt,
      },
    ];
  });
}

export function verifyAppointmentEvidence(
  records: (ContentRecord | undefined)[],
  conversationId: string,
  evidence: AppointmentMessage[],
) {
  if (
    evidence.length !== records.length ||
    evidence.some((message, index) => {
      const record = records[index];
      const payload = record?.payload as
        | {
            text?: string;
            role?: string;
            createdAt?: string;
            kind?: string;
            isInterrupted?: boolean;
          }
        | undefined;
      return (
        record?.deletedAt !== null ||
        record.version < message.version ||
        (message.serverCreatedAt !== undefined &&
          Date.parse(record.createdAt) !== Date.parse(message.serverCreatedAt)) ||
        record.resourceId !== message.id ||
        record.parentId !== conversationId ||
        payload?.text !== message.content ||
        payload.role !== message.role ||
        !payload.createdAt ||
        !Number.isFinite(Date.parse(payload.createdAt)) ||
        Date.parse(payload.createdAt) !== Date.parse(message.createdAt) ||
        (payload.kind !== "text" && payload.kind !== "voice") ||
        payload.isInterrupted === true
      );
    })
  )
    appointmentError(
      "APPOINTMENT_EVIDENCE_CHANGED",
      "确认约定的消息已更新或删除，请重新与旅伴确认。",
    );
}
