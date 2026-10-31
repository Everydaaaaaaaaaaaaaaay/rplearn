import { z } from "zod";
import type { AppointmentSummary } from "./contracts.js";
const prefix = "@lingotrip-memory-v2:";
const payloadSchema = z.object({ content: z.string() });
const metadataSchema = z.object({
  text: z.string(),
  status: z.string().optional(),
  edited: z.boolean().optional(),
  forgotten: z.boolean().optional(),
  archived: z.boolean().optional(),
});
type Memory = AppointmentSummary["memories"][number];
/** A view of current memory management; accepted story and stored summary remain immutable. */
export function currentAppointmentMemory(
  saved: Memory,
  record: { payload: unknown; deletedAt: string | null } | undefined,
): Memory {
  if (record?.deletedAt !== null) return { ...saved, content: "", status: "deleted" };
  const payload = payloadSchema.safeParse(record.payload);
  if (!payload.success) return { ...saved, content: "", status: "unavailable" };
  if (!payload.data.content.startsWith(prefix))
    return {
      ...saved,
      content: payload.data.content,
      status: payload.data.content === saved.content ? "active" : "edited",
    };
  let value: unknown;
  try {
    value = JSON.parse(payload.data.content.slice(prefix.length));
  } catch {
    return { ...saved, content: "", status: "unavailable" };
  }
  const metadata = metadataSchema.safeParse(value);
  if (!metadata.success) return { ...saved, content: "", status: "unavailable" };
  const { text, forgotten, archived, edited, status } = metadata.data;
  return {
    ...saved,
    content: forgotten ? "" : text,
    status: forgotten
      ? "forgotten"
      : archived
        ? "archived"
        : edited
          ? "edited"
          : (status ?? "active"),
  };
}
