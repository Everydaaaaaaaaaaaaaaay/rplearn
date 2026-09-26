import { countEarnedStars } from "./milestone-repository.js";
import { z } from "zod";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import type { LearningContextReader } from "./context.js";
import { LearningEngineRepository } from "./engine-repository.js";
import { levelKeys } from "./content.js";
import type { LearningAnswer } from "./grading.js";
import { learningPolicy, levelProgress } from "./policy.js";

const cursorSchema = z.strictObject({
  characterId: z.uuid(),
  startedAt: z
    .string()
    .max(64)
    .refine((value) => Number.isFinite(Date.parse(value))),
  id: z.uuid(),
});
function decodeCursor(value: string | undefined, characterId: string) {
  if (value === undefined) return undefined;
  try {
    const parsed = cursorSchema.parse(
      JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as unknown,
    );
    if (parsed.characterId !== characterId) throw new Error("游标角色不一致。");
    return { startedAt: parsed.startedAt, id: parsed.id };
  } catch {
    throw new AppError({
      code: "LEARNING_INVALID_CURSOR",
      message: "学习记录翻页位置已失效，请重新打开记录。",
      statusCode: 400,
    });
  }
}

export function createLearningService(
  database: DatabaseResource,
  context: LearningContextReader,
  drainMessages?: (userId: string) => Promise<unknown>,
) {
  const repository = new LearningEngineRepository(database, context);
  return {
    journey: async (userId: string) => {
      await drainMessages?.(userId);
      return repository.inspect(userId, async (session) => {
        const currentLevel = await session.currentLevel();
        const progress = await session.progress();
        const content = await session.publishedContent();
        return {
          currentLevel,
          policy: learningPolicy,
          levels: levelKeys.map((level) => ({
            ...(progress.find((p) => p.level === level) ?? {
              level,
              ...levelProgress(0),
            }),
            publishedUnitCount:
              content.find((entry) => entry.level === level)?.count ?? 0,
          })),
        };
      });
    },
    character: async (userId: string, characterId: string) => {
      await drainMessages?.(userId);
      return repository.inspect(userId, async (session) => {
        const level = await session.currentLevel();
        const state = await session.resolveCharacter(characterId);
        return {
          ...state,
          level,
          ...(await session.availability(state.roleKey, level, characterId)),
        };
      });
    },
    history: (userId: string, characterId: string, limit: number, cursor?: string) => {
      const decoded = decodeCursor(cursor, characterId);
      return repository.inspect(userId, async (session) => {
        await session.resolveCharacter(characterId);
        const page = await session.history(characterId, limit, decoded);
        return {
          items: page.items,
          nextCursor:
            page.next === null
              ? null
              : Buffer.from(JSON.stringify({ characterId, ...page.next })).toString(
                  "base64url",
                ),
        };
      });
    },
    start: async (userId: string, requestId: string, characterId: string) => {
      await drainMessages?.(userId);
      return repository.command(
        userId,
        requestId,
        "start",
        { characterId },
        async (session) => {
          const level = await session.currentLevel();
          await session.resolveCharacter(characterId);
          return session.start(characterId, level);
        },
      );
    },
    attempt: (userId: string, attemptId: string) =>
      repository.read(userId, (session) => session.attempt(attemptId)),
    answer: (
      userId: string,
      requestId: string,
      input: {
        attemptId: string;
        roundId: string;
        questionId: string;
        expectedRevision: number;
        answer: LearningAnswer;
      },
    ) =>
      repository.command(userId, requestId, "answer", input, async (session) => {
        await session.assertRevision(input.attemptId, input.expectedRevision);
        return session.submit(input);
      }),
    finish: (
      userId: string,
      requestId: string,
      input: { attemptId: string; expectedRevision: number; skipRemaining: boolean },
    ) =>
      repository.command(userId, requestId, "finish", input, async (session) => {
        await session.assertRevision(input.attemptId, input.expectedRevision);
        return session.finish(input.attemptId, input.skipRemaining);
      }),
    retry: (
      userId: string,
      requestId: string,
      input: { attemptId: string; expectedRevision: number },
    ) =>
      repository.command(userId, requestId, "retry", input, async (session) => {
        await session.assertRevision(input.attemptId, input.expectedRevision);
        return session.retry(input.attemptId);
      }),
  };
}
export type LearningService = ReturnType<typeof createLearningService>;

/** 向组装层提供事务内读取合同，不暴露学习表。 */
export const createLearningMilestoneReader = () => countEarnedStars;
