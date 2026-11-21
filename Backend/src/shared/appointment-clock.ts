export const DEFAULT_APPOINTMENT_TIME_ZONE = "Asia/Shanghai";

const formatters = new Map<string, Intl.DateTimeFormat>();

function formatter(zone: string): Intl.DateTimeFormat {
  const cached = formatters.get(zone);
  if (cached) return cached;
  const value = new Intl.DateTimeFormat("sv-SE", {
    timeZone: zone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hourCycle: "h23",
  });
  if (formatters.size >= 128) formatters.clear();
  formatters.set(zone, value);
  return value;
}

export function appointmentLocalTime(at: Date, timeZone: string): string {
  return formatter(timeZone).format(at).replace(" ", "T");
}

export function appointmentRelativeDate(localSentAt: string, days: number): string {
  // UTC here is only a calendar arithmetic space. This value is a wall date.
  const calendarDate = new Date(`${localSentAt.slice(0, 10)}T00:00:00Z`);
  calendarDate.setUTCDate(calendarDate.getUTCDate() + days);
  return calendarDate.toISOString().slice(0, 10);
}

export function appointmentMessageClocks(
  messages: { role?: string | undefined; createdAt: string; userTimeZone?: string | undefined }[],
) {
  let zone = DEFAULT_APPOINTMENT_TIME_ZONE;
  return messages.map((message) => {
    if (message.role === "user") {
      try {
        zone = formatter(message.userTimeZone ?? DEFAULT_APPOINTMENT_TIME_ZONE)
          .resolvedOptions().timeZone;
      } catch {
        zone = DEFAULT_APPOINTMENT_TIME_ZONE;
      }
    }
    const sentAt = new Date(message.createdAt);
    return {
      appointmentTimeZone: zone,
      appointmentLocalSentAt: Number.isFinite(sentAt.getTime())
        ? appointmentLocalTime(sentAt, zone)
        : undefined,
    };
  });
}
