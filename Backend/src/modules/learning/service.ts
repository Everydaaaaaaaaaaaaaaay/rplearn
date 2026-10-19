import type { PromotionCourse } from "./promotion-content.js";
import type { LearningLevel } from "./content.js";
import type { LearningDirection } from "./direction.js";
import { z } from "zod";
import type { DatabaseResource } from "../../db/client.js";
import { AppError } from "../../shared/errors.js";
import type { LearningContextReader } from "./context.js";
import { LearningEngineRepository } from "./engine-repository.js";
import { levelKeys } from "./content.js";
import type { LearningAnswer } from "./grading.js";
import { learningPolicy, levelProgress } from "./policy.js";
import { learningAudioObjectKey, type LearningAudioObjectStore } from "./audio.js";

import { learningImageObjectKey } from "./images.js";

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
  assetStore?: LearningAudioObjectStore,
  courses: readonly PromotionCourse[] = [],
) {
  const repository = new LearningEngineRepository(database, context);
  return {
    directions: (userId: string) =>
      repository.read(userId, (session) => session.directions().read()),
    selectDirection: (
      userId: string,
      requestId: string,
      direction: LearningDirection,
      expectedRevision: number,
    ) =>
      repository.command(
        userId,
        requestId,
        "direction.select",
        { direction, expectedRevision },
        (session) => session.directions().select(direction, expectedRevision),
      ),
    debugFill: async (
      userId: string,
      requestId: string,
      characterId: string,
      cycleId: string,
    ) => {
      // UUID 大小写不影响身份；在幂等负载和循环比较前统一为数据库格式。
      const normalizedCycleId = cycleId.toLowerCase();
      await drainMessages?.(userId);
      return repository.command(
        userId,
        requestId,
        "debug.fill",
        { characterId, cycleId: normalizedCycleId },
        async (session) => {
          await session.resolveCharacter(characterId);
          const state = await session.debugFill(characterId, normalizedCycleId);
          const level = await session.currentLevel();
          return {
            ...state,
            level,
            learningDirections: await session.directions().read(),
            ...(await session.availability(state.roleKey, level, characterId)),
          };
        },
      );
    },
    beginPromotion: (userId: string, requestId: string, level: LearningLevel) =>
      repository.command(userId, requestId, "promotion.begin", { level }, (session) =>
        session.promotions(courses).begin(level),
      ),
    promotion: (userId: string, id: string) =>
      repository.read(userId, (session) => session.promotions(courses).read(id)),
    advancePromotion: (
      userId: string,
      requestId: string,
      id: string,
      expectedRevision: number,
    ) =>
      repository.command(
        userId,
        requestId,
        "promotion.advance",
        { id, expectedRevision },
        (session) => session.promotions(courses).advance(id, expectedRevision),
      ),
    completePromotion: (
      userId: string,
      requestId: string,
      id: string,
      expectedRevision: number,
      expectedProfileVersion: number,
    ) =>
      repository.command(
        userId,
        requestId,
        "promotion.complete",
        { id, expectedRevision, expectedProfileVersion },
        (session) =>
          session
            .promotions(courses)
            .complete(id, expectedRevision, expectedProfileVersion, requestId),
      ),
    audio: async (
      userId: string,
      attemptId: string,
      questionId: string,
      assetId?: string,
    ) => {
      const asset = await repository.read(userId, (session) =>
        session.audioAsset(attemptId, questionId, assetId),
      );
      if (!assetStore)
        throw new AppError({
          code: "LEARNING_AUDIO_NOT_READY",
          message: "听力素材暂不可用，请重试或稍后补答。",
          statusCode: 503,
        });
      return {
        assetId: asset.id,
        sha256: asset.sha256,
        byteSize: asset.byteSize,
        durationMs: asset.durationMs,
        contentType: asset.contentType,
        url: await assetStore.createDownloadUrl(learningAudioObjectKey(asset.id), 300),
        expiresAt: new Date(Date.now() + 300_000).toISOString(),
      };
    },
    image: async (
      userId: string,
      attemptId: string,
      questionId: string,
      assetId: string,
    ) => {
      const asset = await repository.read(userId, (session) =>
        session.imageAsset(attemptId, questionId, assetId),
      );
      if (!assetStore)
        throw new AppError({
          code: "LEARNING_IMAGE_NOT_READY",
          message: "图片素材暂不可用，请重试或稍后补答。",
          statusCode: 503,
        });
      return {
        assetId: asset.id,
        sha256: asset.sha256,
        byteSize: asset.byteSize,
        width: asset.width,
        height: asset.height,
        contentType: asset.contentType,
        url: await assetStore.createDownloadUrl(learningImageObjectKey(asset.id), 300),
        expiresAt: new Date(Date.now() + 300_000).toISOString(),
      };
    },
    journey: async (userId: string, completeGroups = false) => {
      await drainMessages?.(userId);
      return repository.inspect(userId, async (session) => {
        const currentLevel = await session.currentLevel();
        const progress = await session.progress();
        const content = await session.publishedContent(completeGroups);
        return {
          currentLevel,
          learningDirections: await session.directions().read(),
          promotion: await session.promotions(courses).eligibility(currentLevel),
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
    character: async (userId: string, characterId: string, completeGroups = false) => {
      await drainMessages?.(userId);
      return repository.inspect(userId, async (session) => {
        const level = await session.currentLevel();
        const state = await session.resolveCharacter(characterId);
        return {
          ...state,
          level,
          learningDirections: await session.directions().read(),
          ...(await session.availability(
            state.roleKey,
            level,
            characterId,
            completeGroups,
          )),
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
    originals: (userId: string, level: LearningLevel) =>
      repository.read(userId, (session) => session.originals(level)),
    start: async (
      userId: string,
      requestId: string,
      characterId: string,
      options: { completeGroups?: boolean; originalUnitId?: string } = {},
    ) => {
      await drainMessages?.(userId);
      return repository.command(
        userId,
        requestId,
        "start",
        {
          characterId,
          ...(options.completeGroups ? { completeGroups: true } : {}),
          ...(options.originalUnitId ? { originalUnitId: options.originalUnitId } : {}),
        },
        async (session) => {
          const level = await session.currentLevel();
          await session.resolveCharacter(characterId);
          return session.start(characterId, level, options);
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
