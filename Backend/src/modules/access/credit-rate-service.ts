import { z } from "zod";
import { AppError } from "../../shared/errors.js";
import type { CreditRateRepository } from "./credit-rate-repository.js";

const schema = z
  .object({
    expectedVersion: z.number().int().positive(),
    scope: z.enum(["global", "users", "auxiliary"]),
    userIds: z
      .array(z.uuid().transform((value) => value.toLowerCase()))
      .max(500)
      .default([]),
    rateUnits: z.number().int().min(0).max(1000000).nullable(),
    changeReason: z.string().trim().min(4).max(500),
  })
  .strict()
  .refine((value) =>
    value.scope !== "users"
      ? value.rateUnits !== null && value.userIds.length === 0
      : value.userIds.length > 0 &&
        new Set(value.userIds).size === value.userIds.length,
  );

export class CreditRateService {
  constructor(private readonly repository: CreditRateRepository) {}
  read() {
    return this.repository.read();
  }
  update(input: unknown, operator: string, command: unknown) {
    const parsed = schema.safeParse(input);
    const id = z.uuid().safeParse(command);
    if (!parsed.success || !id.success)
      throw new AppError({
        code: "INVALID_REQUEST",
        message: "请填写有效用户、0–100 倍倍率、变更理由和操作编号。",
        statusCode: 400,
      });
    return this.repository.update(parsed.data, operator, id.data);
  }
}
