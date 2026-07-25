import { hash, verify } from "@node-rs/argon2";

const PASSWORD_HASH_OPTIONS = {
  algorithm: 2,
  memoryCost: 19_456,
  outputLen: 32,
  parallelism: 1,
  timeCost: 2,
} as const;

export type PasswordHasher = Readonly<{
  hash: (password: string) => Promise<string>;
  verify: (passwordHash: string, password: string) => Promise<boolean>;
}>;

export function createPasswordHasher(): PasswordHasher {
  return {
    hash: async (password) => hash(password, PASSWORD_HASH_OPTIONS),
    verify: async (passwordHash, password) => {
      try {
        return await verify(passwordHash, password);
      } catch {
        return false;
      }
    },
  };
}
