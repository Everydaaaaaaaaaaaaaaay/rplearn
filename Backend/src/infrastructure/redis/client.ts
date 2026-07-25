import { createClient } from "redis";
import type { RuntimeConfig } from "../../config/env.js";

export type RedisResource = Readonly<{
  close: () => Promise<void>;
  connect: () => Promise<void>;
  onError: (listener: (error: Error) => void) => void;
  ping: () => Promise<void>;
  putOneTime: (key: string, value: string, ttlSeconds: number) => Promise<void>;
  takeOneTime: (key: string) => Promise<string | null>;
}>;

export function createRedisResource(config: RuntimeConfig): RedisResource {
  const client = createClient({
    disableOfflineQueue: true,
    socket: {
      connectTimeout: config.redisConnectTimeoutMs,
      reconnectStrategy: (retries) => Math.min(50 * 2 ** retries, 2000),
    },
    url: config.redisUrl,
  });

  return {
    close: async () => {
      if (client.isOpen) {
        await client.close();
      }
    },
    connect: async () => {
      if (!client.isOpen) {
        await client.connect();
      }
    },
    onError: (listener) => {
      client.on("error", listener);
    },
    ping: async () => {
      if (!client.isReady) {
        throw new Error("Redis is not ready");
      }
      await client.ping();
    },
    putOneTime: async (key, value, ttlSeconds) => {
      const result = await client.set(key, value, {
        EX: ttlSeconds,
        NX: true,
      });
      if (result !== "OK") {
        throw new Error("One-time key already exists");
      }
    },
    takeOneTime: async (key) => client.getDel(key),
  };
}
