import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
const readFile = vi.hoisted(() => vi.fn());
vi.mock("node:fs/promises", () => ({ readFile }));
import { requireMaintenanceScope } from "../../src/infrastructure/maintenance.js";

beforeEach(() => {
  vi.stubEnv("NODE_ENV", "production");
  readFile.mockReset();
});
afterEach(() => vi.unstubAllEnvs());
describe("生产维护隔离", () => {
  it("拒绝普通 SSH 会话和伪造环境标记", async () => {
    vi.stubEnv("LINGOTRIP_MAINTENANCE", "1");
    readFile.mockResolvedValue("0::/user.slice/session-1.scope\n");
    await expect(requireMaintenanceScope()).rejects.toThrow("maintenance.sh");
  });
  it("只有受控单元及有效内存边界可以执行", async () => {
    readFile
      .mockResolvedValueOnce("0::/system.slice/lingotrip-maintenance.service\n")
      .mockResolvedValueOnce("268435456\n")
      .mockResolvedValueOnce("0\n");
    await expect(requireMaintenanceScope()).resolves.toBeUndefined();
  });
  it.each([
    ["max", "0"],
    ["536870912", "0"],
    ["268435456", "max"],
  ])("拒绝失效资源边界 %s %s", async (memory, swap) => {
    readFile
      .mockResolvedValueOnce("0::/system.slice/lingotrip-maintenance.service\n")
      .mockResolvedValueOnce(memory)
      .mockResolvedValueOnce(swap);
    await expect(requireMaintenanceScope()).rejects.toThrow("内存与交换区限制");
  });
  it("开发测试不依赖 Linux 生产单元", async () => {
    vi.stubEnv("NODE_ENV", "test");
    await requireMaintenanceScope();
    expect(readFile).not.toHaveBeenCalled();
  });
});
