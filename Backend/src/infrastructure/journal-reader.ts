import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execute = promisify(execFile);
export const JOURNAL_LIMIT = 20_000;

export async function readServiceJournal(hours: number): Promise<string> {
  if (![1, 6, 24, 72].includes(hours)) throw new Error("日志时间范围无效");
  const { stdout, stderr } = await execute(
    "journalctl",
    [
      "--unit=lingotrip-api.service",
      "--unit=lingotrip-worker.service",
      `--since=-${String(hours)}h`,
      `--lines=${String(JOURNAL_LIMIT + 1)}`,
      "--output=json",
      "--output-fields=MESSAGE,_SYSTEMD_UNIT,__REALTIME_TIMESTAMP",
      "--no-pager",
    ],
    { timeout: 8000, maxBuffer: 32 * 1024 * 1024, encoding: "utf8" },
  );
  if (/permission|not seeing|No journal files/i.test(stderr)) {
    throw new Error("服务日志不可读");
  }
  return stdout;
}
