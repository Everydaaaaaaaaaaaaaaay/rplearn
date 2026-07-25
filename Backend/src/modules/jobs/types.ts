export const AUTH_EMAIL_VERIFICATION_JOB = "auth.email_verification";
export const AUTH_PASSWORD_RESET_JOB = "auth.password_reset";

export type AuthEmailJobType =
  typeof AUTH_EMAIL_VERIFICATION_JOB | typeof AUTH_PASSWORD_RESET_JOB;

export type AuthEmailJobPayload = Readonly<{
  email: string;
  token: string;
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
