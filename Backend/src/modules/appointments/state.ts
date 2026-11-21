import { AppError } from "../../shared/errors.js";
import type {
  Appointment,
  AppointmentChoice,
  AppointmentMessage,
  AppointmentSession,
} from "./contracts.js";
export function appointmentError(
  code: string,
  message: string,
  statusCode = 409,
): never {
  throw new AppError({ code, message, statusCode });
}
export function resolveAppointmentTime(local: string, timeZone: string): string {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?$/.test(local))
    appointmentError("APPOINTMENT_TIME_UNCLEAR", "请确认完整的当地日期与时间。", 422);
  const canonical = local.length === 16 ? `${local}:00` : local;
  const naive = new Date(`${canonical}Z`).getTime();
  if (
    !Number.isFinite(naive) ||
    new Date(naive).toISOString().slice(0, 19) !== canonical
  )
    appointmentError("APPOINTMENT_TIME_UNCLEAR", "日期无效。", 422);
  let formatter: Intl.DateTimeFormat;
  try {
    formatter = new Intl.DateTimeFormat("sv-SE", {
      timeZone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    });
  } catch {
    appointmentError("APPOINTMENT_TIME_UNCLEAR", "时区无效。", 422);
  }
  const candidates: number[] = [];
  for (let minutes = -14 * 60; minutes <= 14 * 60; minutes += 15) {
    const timestamp = naive + minutes * 60_000;
    if (formatter.format(new Date(timestamp)).replace(" ", "T") === canonical)
      candidates.push(timestamp);
  }
  if (candidates.length !== 1)
    appointmentError(
      "APPOINTMENT_TIME_UNCLEAR",
      "夏令时时刻不明确，请与旅伴确认另一个时间。",
      422,
    );
  const candidate = candidates[0];
  if (candidate === undefined)
    appointmentError("APPOINTMENT_TIME_UNCLEAR", "当地时间无效。", 422);
  return new Date(candidate).toISOString();
}
export function assertEntry(appointment: Appointment, city: string, now: Date) {
  if (appointment.status === "in_progress") return;
  if (appointment.status !== "confirmed")
    appointmentError("APPOINTMENT_CLOSED", "这次约定已结束。");
  if (city !== appointment.cityId)
    appointmentError("APPOINTMENT_WRONG_CITY", "请先前往约定所在的应用城市。");
  if (
    now.getTime() < Date.parse(appointment.windowOpensAt) ||
    now.getTime() > Date.parse(appointment.windowClosesAt)
  )
    appointmentError(
      "APPOINTMENT_OUTSIDE_WINDOW",
      "尚未到赴约时间，或已错过首次入场窗口。",
    );
}
export function validateEvidence(
  evidence: { messageId: string; version: number }[],
  messages: AppointmentMessage[],
) {
  const cited = evidence.map((e) =>
    messages.find((m) => m.id === e.messageId && m.version === e.version),
  );
  if (
    cited.some((m) => !m) ||
    !cited.some((m) => m?.role === "user") ||
    !cited.some((m) => m?.role === "assistant")
  )
    appointmentError(
      "APPOINTMENT_UNCONFIRMED",
      "需要双方消息确认后才能建立约定。",
      422,
    );
}
export function resolveAction(session: AppointmentSession, input: AppointmentChoice) {
  const block = session.blocks.at(-1);
  if (!block || block.ending)
    appointmentError("APPOINTMENT_CLOSED", "这段故事已结束。");
  if (
    [
      input.choiceId !== undefined,
      input.input !== undefined,
      input.finish === true,
    ].filter(Boolean).length !== 1
  )
    appointmentError("INVALID_REQUEST", "请选择一项行动。", 400);
  if (input.finish)
    return { input: "我想先走，今天就到这里吧。", custom: true, finish: true };
  if (input.input !== undefined) {
    const text = input.input.trim();
    if (!text || text.length > 2000)
      appointmentError("INVALID_REQUEST", "自定义输入需要 1–2000 字。", 400);
    return { input: text, custom: true, finish: false };
  }
  const choice = block.choices.find((c) => c.id === input.choiceId);
  if (!choice)
    appointmentError("APPOINTMENT_CHOICE_NOT_FOUND", "请选择当前段落中的选项。", 400);
  return { input: choice.english, custom: false, finish: false };
}

/** Annotation/translation/coaching revisions do not change the agreement's message facts. */
export function appointmentMessageFacts(messages: AppointmentMessage[]) {
  return messages.map(({ id, role, content, createdAt, serverCreatedAt }) => ({
    id,
    role,
    content,
    createdAt: Date.parse(createdAt),
    serverCreatedAt: Date.parse(serverCreatedAt ?? createdAt),
  }));
}
