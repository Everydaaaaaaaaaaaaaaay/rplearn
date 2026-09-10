import type { ServerResponse } from "node:http";

type SseResponse = Pick<
  ServerResponse,
  "destroyed" | "writableEnded" | "write" | "once" | "off"
>;

/** A disconnected or backpressured client must not stop upstream usage collection. */
export function writeSseEvent(
  response: SseResponse,
  event: string,
  data: unknown,
): Promise<boolean> {
  if (response.destroyed || response.writableEnded) return Promise.resolve(false);
  return new Promise((resolve) => {
    const finish = (writable: boolean) => {
      response.off("drain", drained);
      response.off("close", closed);
      response.off("error", closed);
      resolve(writable);
    };
    const drained = () => finish(true);
    const closed = () => finish(false);
    response.once("drain", drained);
    response.once("close", closed);
    response.once("error", closed);
    try {
      if (response.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`)) {
        finish(true);
      }
    } catch {
      closed();
    }
  });
}
