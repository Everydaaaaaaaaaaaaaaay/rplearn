import { z } from "zod";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import { LearningRepository } from "./repository.js";
const stateSchema = z
  .object({
    enabled: z.boolean(),
    ledger: z
      .object({
        version: z.literal(1),
        ruleRevision: z.number().int().min(1).max(4).optional(),
      })
      .loose(),
    pending: z.array(z.unknown()),
    listening: z.array(z.unknown()),
  })
  .loose();
export function validateLearningPayload(payload: string): void {
  if (Buffer.byteLength(payload, "utf8") > 2_097_152)
    throw new AppError({
      code: "LEARNING_STATE_TOO_LARGE",
      message: "Learning history exceeds the sync limit.",
      statusCode: 413,
    });
  let value: unknown;
  try {
    value = JSON.parse(payload) as unknown;
  } catch {
    value = null;
  }
  if (!stateSchema.safeParse(value).success)
    throw new AppError({
      code: "INVALID_LEARNING_STATE",
      message: "Unsupported learning state.",
      statusCode: 400,
    });
}
export function createLearningService(database: DatabaseResource) {
  const repository = new LearningRepository(database);
  return {
    read: (userId: string) => repository.read(userId),
    save: async (userId: string, revision: number, payload: string) => {
      validateLearningPayload(payload);
      const saved = await repository.save(userId, revision, payload);
      if (!saved)
        throw new AppError({
          code: "LEARNING_STATE_CONFLICT",
          message: "Learning records changed on another device. Refresh before saving.",
          statusCode: 409,
        });
      return saved;
    },
  };
}
export type LearningService = ReturnType<typeof createLearningService>;
