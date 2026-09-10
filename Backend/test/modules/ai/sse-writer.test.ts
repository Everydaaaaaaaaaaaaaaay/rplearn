import { EventEmitter } from "node:events";
import type { ServerResponse } from "node:http";
import { describe, expect, it, vi } from "vitest";
import { writeSseEvent } from "../../../src/modules/ai/sse-writer.js";

function response(backpressured = false) {
  return Object.assign(new EventEmitter(), {
    destroyed: false,
    writableEnded: false,
    write: vi.fn(() => !backpressured),
  });
}
function write(raw: ReturnType<typeof response>) {
  return writeSseEvent(raw as unknown as ServerResponse, "delta", { text: "hello" });
}
describe("SSE settlement delivery", () => {
  it("does not wait forever for drain after the client closes", async () => {
    const raw = response(true);
    const pending = write(raw);
    raw.destroyed = true;
    raw.emit("close");
    expect(await pending).toBe(false);
    expect(raw.eventNames()).toEqual([]);
    expect(await write(raw)).toBe(false);
    expect(raw.write).toHaveBeenCalledTimes(1);
  });
  it("resumes after backpressure and removes all listeners", async () => {
    const raw = response(true);
    const pending = write(raw);
    raw.emit("drain");
    expect(await pending).toBe(true);
    expect(raw.eventNames()).toEqual([]);
  });
  it("treats transport errors as a closed downstream, not a provider failure", async () => {
    const raw = response(true);
    const pending = write(raw);
    raw.emit("error", new Error("socket closed"));
    expect(await pending).toBe(false);
    expect(raw.eventNames()).toEqual([]);
  });
  it("writes normal SSE and skips an ended response", async () => {
    const raw = response();
    expect(await write(raw)).toBe(true);
    expect(raw.write).toHaveBeenCalledWith('event: delta\ndata: {"text":"hello"}\n\n');
    expect(raw.eventNames()).toEqual([]);
    raw.writableEnded = true;
    expect(await write(raw)).toBe(false);
  });
});
