import type { TransactionSql } from "postgres";
import type { ContentRecord, ContentResourceType } from "../content/types.js";
import type { AiMessage } from "../ai/types.js";

export interface ChatGeneration {
  id: string;
  status: "queued" | "dispatched" | "completed" | "failed" | "uncertain";
  partialText: string;
  inputMessageIds: string[];
  errorCode: string | null;
}
export interface ChatState {
  protocolVersion: 1;
  conversationId: string;
  revision: number;
  lastSequence: number;
  hasMore: boolean;
  generation: ChatGeneration | null;
  coveredMessageIds: string[];
  records: ContentRecord[];
}
export interface ChatGenerationInput {
  userId: string;
  generationId: string;
  conversationId: string;
  characterId: string;
  inputMessageIds: string[];
  messages: AiMessage[];
  voiceLeaseId?: string;
  learningChat?: { conversationId: string; userMessageId: string; cycleId: string };
}
export interface ChatContentAccess {
  read(
    sql: TransactionSql,
    userId: string,
    type: ContentResourceType,
    id: string,
  ): Promise<ContentRecord | undefined>;
  list(
    sql: TransactionSql,
    userId: string,
    type: ContentResourceType,
    parentId: string | null,
    limit?: number,
  ): Promise<ContentRecord[]>;
  write(
    sql: TransactionSql,
    userId: string,
    type: ContentResourceType,
    id: string,
    parentId: string | null,
    payload: Record<string, unknown>,
  ): Promise<ContentRecord>;
  messages(
    sql: TransactionSql,
    userId: string,
    conversationId: string,
    after: number,
    limit: number,
  ): Promise<ContentRecord[]>;
  learner?(sql: TransactionSql, userId: string): Promise<Record<string, unknown>>;
  onAdopt?(
    sql: TransactionSql,
    userId: string,
    oldConversationId: string,
    canonicalId: string,
  ): Promise<void>;
  onMessage?(sql: TransactionSql, userId: string, record: ContentRecord): Promise<void>;
  rewrite(
    sql: TransactionSql,
    userId: string,
    record: ContentRecord,
    parentId: string | null,
    payload: Record<string, unknown>,
  ): Promise<ContentRecord>;
}
export interface ChatProcessorOptions {
  generate(
    input: ChatGenerationInput,
    onDelta: (partial: string) => Promise<void>,
  ): Promise<string>;
  operationPending?: (userId: string, generationId: string) => Promise<boolean>;
  recover?: (input: ChatGenerationInput) => Promise<{ content: string } | null>;
  coalesceMilliseconds?: number;
  leaseMilliseconds?: number;
}
