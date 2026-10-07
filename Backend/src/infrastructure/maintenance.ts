import { readFile } from "node:fs/promises";

/** 防止原生生产维护命令绕过统一队列；不是对拥有 root 权限者的安全隔离。 */
export async function requireMaintenanceScope(): Promise<void> {
  if (
    process.env.NODE_ENV !== "production" &&
    !process.cwd().startsWith("/opt/lingotrip/")
  )
    return;
  const scope = await readFile("/proc/self/cgroup", "utf8").catch(() => "");
  if (!scope.split("\n").includes("0::/system.slice/lingotrip-maintenance.service"))
    throw new Error("生产维护必须通过 ops/native-server/maintenance.sh 执行。");
  const root = "/sys/fs/cgroup/system.slice/lingotrip-maintenance.service";
  const [memory, swap] = await Promise.all([
    readFile(`${root}/memory.max`, "utf8"),
    readFile(`${root}/memory.swap.max`, "utf8"),
  ]);
  if (
    !(Number(memory.trim()) > 0 && Number(memory.trim()) <= 256 * 1024 ** 2) ||
    swap.trim() !== "0"
  )
    throw new Error("维护进程缺少有效内存与交换区限制，已停止。");
}

/** 只记录阶段与资源用量，不输出题目、凭证或连接信息。 */
export async function maintenanceStage<T>(
  stage: string,
  work: () => Promise<T>,
): Promise<T> {
  const started = Date.now();
  const report = (state: string) =>
    process.stderr.write(
      `${JSON.stringify({
        event: "maintenance.stage",
        stage,
        state,
        elapsedMs: Date.now() - started,
        rssMiB: Math.round(process.memoryUsage().rss / 1024 ** 2),
      })}\n`,
    );
  report("开始");
  try {
    const result = await work();
    report("完成");
    return result;
  } catch (error) {
    report("失败");
    throw error;
  }
}
