export type ReadinessCheck = Readonly<{
  check: () => Promise<void>;
  name: string;
}>;

export type ReadinessResult = Readonly<{
  name: string;
  status: "available" | "unavailable";
}>;

async function runWithTimeout(
  operation: Promise<void>,
  timeoutMs: number,
): Promise<void> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_resolve, reject) => {
    timer = setTimeout(() => {
      reject(new Error("Readiness check timed out"));
    }, timeoutMs);
  });

  try {
    await Promise.race([operation, timeout]);
  } finally {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
  }
}

export async function checkReadiness(
  checks: readonly ReadinessCheck[],
  timeoutMs: number,
): Promise<readonly ReadinessResult[]> {
  return Promise.all(
    checks.map(async (check): Promise<ReadinessResult> => {
      try {
        await runWithTimeout(check.check(), timeoutMs);
        return {
          name: check.name,
          status: "available",
        };
      } catch {
        return {
          name: check.name,
          status: "unavailable",
        };
      }
    }),
  );
}
