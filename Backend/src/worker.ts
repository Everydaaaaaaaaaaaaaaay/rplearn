import { createLearningChatService } from "./modules/learning/chat-service.js";
import { learningRoleKey } from "./modules/learning/context.js";
import { createContentReadService } from "./modules/content/service.js";
import { createDomainLearningContext } from "./modules/domain/service.js";
import { DictionaryExampleGenerationRepository } from "./modules/dictionary-translation/generation-repository.js";
import { DictionaryExampleCatalogRepository } from "./modules/dictionary-translation/catalog-repository.js";
import { createDictionaryExampleCatalogService } from "./modules/dictionary-translation/catalog-service.js";
import { createDictionaryExampleGenerationProcessor } from "./modules/dictionary-translation/generation-processor.js";
import "dotenv/config";
import { shutdownTelemetry } from "./instrumentation.js";
import { setTimeout as delay } from "node:timers/promises";
import pino from "pino";
import { createLoggerOptions } from "./app/logger.js";
import { ConfigurationError, loadConfig } from "./config/env.js";
import { createDatabase } from "./db/client.js";
import { assertMigrationsCurrent } from "./db/migrate.js";
import { createSmtpAuthNotifier } from "./modules/auth/notifier.js";
import { createJobPayloadCipher } from "./modules/jobs/crypto.js";
import { JobRepository } from "./modules/jobs/repository.js";
import { JobWorker } from "./modules/jobs/worker.js";
import { newEntityId } from "./shared/id.js";
import { createAccountService } from "./modules/account/service.js";
import { createCredentialSealer } from "./modules/auth/apple/credential-crypto.js";
import { createAppleTokenRevoker } from "./modules/auth/apple/token-revoker.js";
import { createMediaObjectStore } from "./modules/media/object-store.js";
import { createMediaService } from "./modules/media/service.js";
import { createRedisResource } from "./infrastructure/redis/client.js";
import { createBillingService } from "./modules/billing/service.js";
import { createDeepSeekClient } from "./modules/ai/deepseek/client.js";
import { createOpenRouterClient } from "./modules/ai/openrouter/client.js";
import { AiCatalogRepository } from "./modules/ai/catalog-repository.js";
import { createAiCatalogService } from "./modules/ai/catalog-service.js";
import { createAiService } from "./modules/ai/service.js";
import { createDictionaryTranslationProcessor } from "./modules/dictionary-translation/processor.js";
import { createNpcService } from "./modules/npc/service.js";

async function main(): Promise<void> {
  let config: ReturnType<typeof loadConfig>;
  try {
    config = loadConfig();
  } catch (error) {
    if (error instanceof ConfigurationError) {
      process.stderr.write(`${error.message}\n`);
      process.exitCode = 1;
      return;
    }
    throw error;
  }

  const logger = pino(createLoggerOptions(config.logLevel));
  const database = createDatabase(config);
  const redis = createRedisResource(config);
  redis.onError((error) => {
    logger.error({ errorName: error.name }, "Redis client error in background worker");
  });
  const controller = new AbortController();
  const workerId = `worker-${newEntityId()}`;
  const mediaObjectStore = config.mediaStorageEnabled
    ? createMediaObjectStore(config)
    : undefined;
  const mediaService =
    mediaObjectStore === undefined
      ? undefined
      : createMediaService(config, database, mediaObjectStore);
  const accountService = createAccountService(config, database, {
    onAppleRevocationUnavailable: (fields) => {
      logger.warn(fields, "Apple token revocation was unavailable during deletion");
    },
    ...(config.appleAuthEnabled
      ? {
          appleTokenRevoker: await createAppleTokenRevoker(config),
          credentialSealer: createCredentialSealer(config),
        }
      : {}),
    ...(mediaObjectStore === undefined
      ? {}
      : { deleteMediaObjects: mediaObjectStore.deleteObjects }),
  });
  const openRouter = createOpenRouterClient(config);
  const aiCatalog = createAiCatalogService(
    config,
    new AiCatalogRepository(database),
    openRouter,
  );
  const aiService = createAiService(
    config,
    database,
    redis,
    createBillingService(database),
    createDeepSeekClient(config),
    { catalog: aiCatalog, openRouter },
  );
  const dictionaryTranslationProcessor = createDictionaryTranslationProcessor(
    database,
    {
      completionClient: {
        complete: (userId, messages) =>
          aiService.complete(userId, {
            maxOutputTokens: 500,
            messages,
            responseFormat: "json_object",
            task: "dictionary_example_translation",
          }),
        runtimeModelVersion: async () => {
          const route = await aiService.routeIdentity("dictionary_example_translation");
          return `${route.model}@config-${String(route.configVersion)}`;
        },
      },
    },
  );
  const dictionaryExampleProcessor = createDictionaryExampleGenerationProcessor(
    new DictionaryExampleGenerationRepository(database),
    createDictionaryExampleCatalogService(
      new DictionaryExampleCatalogRepository(database),
    ),
    (userId, messages, operationId) =>
      aiService.complete(userId, {
        task: "dictionary_example_translation",
        messages,
        responseFormat: "json_object",
        maxOutputTokens: 1400,
        operationId,
      }),
  );
  const worker = new JobWorker({
    cipher: createJobPayloadCipher(config),
    config,
    logger,
    notifier: createSmtpAuthNotifier(config),
    processAccountPurge: accountService.processDeletion,
    ...(mediaService === undefined
      ? {}
      : { processMediaDelete: mediaService.processDeletion }),
    processDictionaryTranslation: dictionaryTranslationProcessor.process,
    processDictionaryExamples: dictionaryExampleProcessor.process,
    repository: new JobRepository(database),
    workerId,
  });
  const learningContent = createContentReadService(database);
  const learningProfile = createDomainLearningContext(database);
  const learningChat = createLearningChatService(
    database,
    {
      profile: learningProfile.difficulty,
      character: async (sql, userId, characterId) =>
        learningRoleKey(await learningContent.character(sql, userId, characterId)),
    },
    learningContent,
  );
  let nextLearningPollAt = 0;
  const npcService = createNpcService(database);
  let nextAvatarPollAt = 0;
  let closing = false;

  const shutdown = (signal: NodeJS.Signals): void => {
    if (closing) {
      return;
    }
    closing = true;
    logger.info({ signal, workerId }, "Worker shutdown started");
    controller.abort();
  };
  process.once("SIGINT", () => shutdown("SIGINT"));
  process.once("SIGTERM", () => shutdown("SIGTERM"));

  try {
    await redis.connect();
    await assertMigrationsCurrent(database);
    logger.info({ workerId }, "Worker started");
    while (!controller.signal.aborted) {
      if (Date.now() >= nextLearningPollAt) {
        nextLearningPollAt = Date.now() + 5_000;
        try {
          await learningChat.processPending();
        } catch (error) {
          logger.error(
            { errorName: error instanceof Error ? error.name : "UnknownError" },
            "学习消息计数暂未完成，下轮重放",
          );
        }
      }
      if (Date.now() >= nextAvatarPollAt) {
        nextAvatarPollAt = Date.now() + 60_000;
        try {
          const retry = await npcService.retryPendingAvatars();
          if (retry.attempted > 0) logger.info(retry, "Pending NPC portraits retried");
        } catch (error) {
          logger.error(
            { errorName: error instanceof Error ? error.name : "UnknownError" },
            "NPC portrait retry failed",
          );
        }
      }
      try {
        const result = await worker.runOnce();
        if (result !== "idle") {
          continue;
        }
      } catch (error) {
        logger.error(
          {
            errorName: error instanceof Error ? error.name : "UnknownError",
            workerId,
          },
          "Worker polling failed",
        );
      }

      try {
        await delay(config.jobPollIntervalMs, undefined, {
          signal: controller.signal,
        });
      } catch (error) {
        if (!(error instanceof Error) || error.name !== "AbortError") {
          throw error;
        }
      }
    }
  } finally {
    await Promise.allSettled([redis.close(), database.close()]);
    logger.info({ workerId }, "Worker stopped");
    await shutdownTelemetry();
  }
}

void main().catch((error: unknown) => {
  process.stderr.write(
    `${error instanceof Error ? error.name : "UnknownWorkerError"}\n`,
  );
  process.exitCode = 1;
});
