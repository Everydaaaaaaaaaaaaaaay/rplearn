export const AUTH_EMAIL_VERIFICATION_JOB = "auth.email_verification";
export const AUTH_PASSWORD_RESET_JOB = "auth.password_reset";
export const ACCOUNT_PURGE_JOB = "account.purge";
export const MEDIA_DELETE_JOB = "media.delete";
export const DICTIONARY_EXAMPLE_GENERATION_JOB = "dictionary.example_generation";
export const DICTIONARY_EXAMPLE_TRANSLATION_JOB = "dictionary.example_translation";

export type AuthEmailJobType =
  typeof AUTH_EMAIL_VERIFICATION_JOB | typeof AUTH_PASSWORD_RESET_JOB;

export type AuthEmailJobPayload = Readonly<{
  email: string;
  token: string;
}>;

export type JobEmailNotifier = Readonly<{
  sendEmailVerification: (email: string, token: string) => Promise<void>;
  sendPasswordReset: (email: string, token: string) => Promise<void>;
}>;

export type AccountPurgeJobPayload = Readonly<{
  requestId: string;
  userId: string;
}>;

export type MediaDeleteJobPayload = Readonly<{
  assetId: string;
  objectKey: string;
}>;

export type PreparedJob = Readonly<{
  availableAt: Date;
  id: string;
  keyVersion: string;
  maxAttempts: number;
  nonce: Buffer;
  payloadCiphertext: Buffer;
  tag: Buffer;
  type: string;
  uniqueKey?: string;
  userId?: string;
}>;

export type ClaimedJob = Readonly<{
  attempts: number;
  id: string;
  keyVersion: string;
  maxAttempts: number;
  nonce: Buffer;
  payloadCiphertext: Buffer;
  tag: Buffer;
  type: string;
}>;
