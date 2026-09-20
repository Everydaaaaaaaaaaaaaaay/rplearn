import { SpanStatusCode, trace } from "@opentelemetry/api";
import { z } from "zod";
import type { RuntimeConfig } from "../../config/env.js";
import type { JobPayloadCipher } from "./crypto.js";
import type { JobFailureResult, JobRepository } from "./repository.js";
import {
  ACCOUNT_PURGE_JOB,
  AUTH_EMAIL_VERIFICATION_JOB,
  AUTH_PASSWORD_RESET_JOB,
  DICTIONARY_EXAMPLE_TRANSLATION_JOB,
  DICTIONARY_EXAMPLE_GENERATION_JOB,
  MEDIA_DELETE_JOB,
  type ClaimedJob,
  type JobEmailNotifier,
} from "./types.js";

const authEmailPayloadSchema = z.object({
  email: z.email().max(254),
  token: z.string().min(32).max(1024),
});
const accountPurgePayloadSchema = z.object({
  requestId: z.uuid(),
  userId: z.uuid(),
});
const mediaDeletePayloadSchema = z.object({
  assetId: z.uuid(),
  objectKey: z
    .string()
    .regex(/^[0-9a-f-]{36}\/[0-9a-f-]{36}$/i)
    .max(73),
});
const dictionaryTranslationPayloadSchema = z
  .object({
    attempt: z.number().int().positive(),
    cacheKey: z.string().regex(/^[0-9a-f]{64}$/),
    userId: z.uuid(),
  })
  .strict();
const dictionaryExamplesPayloadSchema = z
  .object({
    lemma: z.string().min(1).max(120),
    revision: z.number().int().positive(),
    userId: z.uuid(),
  })
  .strict();
const OBSERVABLE_JOB_TYPES: ReadonlySet<string> = new Set([
  ACCOUNT_PURGE_JOB,
  AUTH_EMAIL_VERIFICATION_JOB,
  AUTH_PASSWORD_RESET_JOB,
  DICTIONARY_EXAMPLE_TRANSLATION_JOB,
  DICTIONARY_EXAMPLE_GENERATION_JOB,
  MEDIA_DELETE_JOB,
]);

export type JobRunResult = "idle" | "succeeded" | JobFailureResult;

type WorkerLogger = Readonly<{
  error: (fields: Record<string, unknown>, message: string) => void;
  info: (fields: Record<string, unknown>, message: string) => void;
  warn: (fields: Record<string, unknown>, message: string) => void;
}>;

type JobWorkerDependencies = Readonly<{
  cipher: JobPayloadCipher;
  config: RuntimeConfig;
  logger: WorkerLogger;
  notifier: JobEmailNotifier;
  processAccountPurge?: (
    payload: z.infer<typeof accountPurgePayloadSchema>,
  ) => Promise<void>;
  processMediaDelete?: (
    payload: z.infer<typeof mediaDeletePayloadSchema>,
  ) => Promise<void>;
  processDictionaryExamples?: (
    payload: z.infer<typeof dictionaryExamplesPayloadSchema>,
    attempt: number,
  ) => Promise<void>;
  processDictionaryTranslation?: (
    payload: z.infer<typeof dictionaryTranslationPayloadSchema>,
  ) => Promise<void>;
  repository: Pick<JobRepository, "claim" | "complete" | "fail">;
  workerId: string;
}>;

function retryDelay(baseSeconds: number, attempts: number): number {
  return Math.min(3600, baseSeconds * 2 ** Math.max(0, attempts - 1));
}

function safeErrorName(error: unknown): string {
  return error instanceof Error ? error.name.slice(0, 200) : "UnknownJobError";
}

export class JobWorker {
  constructor(private readonly dependencies: JobWorkerDependencies) {}

  private async dispatch(job: ClaimedJob): Promise<void> {
    const payload = this.dependencies.cipher.open(job);
    switch (job.type) {
      case AUTH_EMAIL_VERIFICATION_JOB: {
        const email = authEmailPayloadSchema.parse(payload);
        await this.dependencies.notifier.sendEmailVerification(
          email.email,
          email.token,
        );
        return;
      }
      case AUTH_PASSWORD_RESET_JOB: {
        const email = authEmailPayloadSchema.parse(payload);
        await this.dependencies.notifier.sendPasswordReset(email.email, email.token);
        return;
      }
      case ACCOUNT_PURGE_JOB:
        if (this.dependencies.processAccountPurge === undefined) {
          throw new Error("AccountPurgeHandlerUnavailable");
        }
        await this.dependencies.processAccountPurge(
          accountPurgePayloadSchema.parse(payload),
        );
        return;
      case MEDIA_DELETE_JOB:
        if (this.dependencies.processMediaDelete === undefined) {
          throw new Error("MediaDeleteHandlerUnavailable");
        }
        await this.dependencies.processMediaDelete(
          mediaDeletePayloadSchema.parse(payload),
        );
        return;
      case DICTIONARY_EXAMPLE_GENERATION_JOB:
        if (this.dependencies.processDictionaryExamples === undefined)
          throw new Error("DictionaryExamplesHandlerUnavailable");
        await this.dependencies.processDictionaryExamples(
          dictionaryExamplesPayloadSchema.parse(payload),
          job.attempts,
        );
        return;
      case DICTIONARY_EXAMPLE_TRANSLATION_JOB:
        if (this.dependencies.processDictionaryTranslation === undefined) {
          throw new Error("DictionaryTranslationHandlerUnavailable");
        }
        await this.dependencies.processDictionaryTranslation(
          dictionaryTranslationPayloadSchema.parse(payload),
        );
        return;
      default:
        throw new Error("UnsupportedJobType");
    }
  }

  async runOnce(now = new Date()): Promise<JobRunResult> {
    const job = await this.dependencies.repository.claim(
      this.dependencies.workerId,
      now,
      this.dependencies.config.jobLeaseSeconds,
    );
    if (job === undefined) {
      return "idle";
    }

    return trace.getTracer("lingotrip.jobs").startActiveSpan(
      "job.process",
      {
        attributes: {
          "lingotrip.job.attempt": job.attempts,
          "lingotrip.job.type": OBSERVABLE_JOB_TYPES.has(job.type) ? job.type : "other",
        },
      },
      async (span): Promise<JobRunResult> => {
        try {
          await this.dispatch(job);
          const completed = await this.dependencies.repository.complete(
            job.id,
            this.dependencies.workerId,
            new Date(),
          );
          if (!completed) {
            span.setAttribute("lingotrip.job.result", "lease_lost");
            span.setStatus({
              code: SpanStatusCode.ERROR,
              message: "JobLeaseLost",
            });
            this.dependencies.logger.warn(
              { jobId: job.id, jobType: job.type },
              "Job lease was lost before completion",
            );
            return "lease_lost";
          }
          span.setAttribute("lingotrip.job.result", "succeeded");
          span.setStatus({ code: SpanStatusCode.OK });
          this.dependencies.logger.info(
            { attempts: job.attempts, jobId: job.id, jobType: job.type },
            "Job completed",
          );
          return "succeeded";
        } catch (error) {
          const errorName = safeErrorName(error);
          const result = await this.dependencies.repository.fail(
            job,
            this.dependencies.workerId,
            new Date(),
            retryDelay(this.dependencies.config.jobRetryBaseSeconds, job.attempts),
            errorName,
          );
          span.setAttribute("lingotrip.job.result", result);
          span.setStatus({
            code: SpanStatusCode.ERROR,
            message: errorName,
          });
          this.dependencies.logger.error(
            {
              attempts: job.attempts,
              jobId: job.id,
              jobType: job.type,
              result,
              errorName,
            },
            "Job execution failed",
          );
          return result;
        } finally {
          span.end();
        }
      },
    );
  }
}
