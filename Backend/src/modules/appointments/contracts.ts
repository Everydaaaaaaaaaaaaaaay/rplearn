import type { TransactionSql } from "postgres";

export interface Appointment {
  id: string;
  characterId: string;
  title: string;
  cityId: string;
  cityName: string;
  timeZone: string;
  userTimeZone?: string;
  placeName: string;
  startsAt: string;
  endsAt: string;
  windowOpensAt: string;
  windowClosesAt: string;
  status: "confirmed" | "in_progress" | "completed" | "cancelled" | "expired";
  revision: number;
  timelineEvents?: AppointmentTimelineEvent[];
}
export interface AppointmentTimelineEvent {
  id: string;
  kind:
    | "confirmed"
    | "rescheduled"
    | "relocated"
    | "rescheduledAndRelocated"
    | "cancelled"
    | "expired"
    | "started"
    | "completed";
  occurredAt: string;
  conversationId: string;
  messageId?: string;
  title: string;
  placeName: string;
  startsAt: string;
  timeZone: string;
  userTimeZone?: string;
}
export interface AppointmentBlock {
  id: string;
  sequence: number;
  location: string;
  beats: { speaker: "narrator" | "character"; english: string; chinese: string }[];
  choices: { id: string; english: string; chinese: string }[];
  ending: boolean;
  presentation?: "paragraphs";
}
export interface AppointmentDecision {
  id: string;
  blockId: string;
  input: string;
  custom: boolean;
  outcome: string;
  createdAt: string;
}
export interface AppointmentSession {
  id: string;
  blocks: AppointmentBlock[];
  decisions: AppointmentDecision[];
}
export interface AppointmentSummary {
  title: string;
  reflection: string;
  affinity: {
    status: "settled" | "pending";
    before?: number;
    after?: number;
    delta?: number;
    reason: string;
  };
  memories: { id: string; content: string; status: string }[];
}
export interface AppointmentDetail {
  appointment: Appointment;
  session: AppointmentSession | null;
  summary: AppointmentSummary | null;
  serverNow: string;
}
export interface AppointmentCommand {
  commandId: string;
  expectedRevision: number;
}
export interface AppointmentChoice extends AppointmentCommand {
  choiceId?: string;
  input?: string;
  finish?: true;
}
export interface AppointmentMessage {
  /** Immutable server save time; relative dates must use this over client payload timestamps. */
  serverCreatedAt?: string;
  userTimeZone?: string;
  id: string;
  version: number;
  role: "user" | "assistant";
  content: string;
  createdAt: string;
}
export interface AppointmentCharacter {
  id: string;
  name: string;
  cityId: string;
  cityName: string;
  timeZone: string;
  persona: unknown;
}
export interface AppointmentContextReader {
  verifyEvidence?: (
    sql: TransactionSql,
    userId: string,
    conversationId: string,
    evidence: AppointmentMessage[],
  ) => Promise<void>;
  character(
    sql: TransactionSql,
    userId: string,
    characterId: string,
  ): Promise<AppointmentCharacter>;
  messages(
    sql: TransactionSql,
    userId: string,
    characterId: string,
    conversationId: string,
  ): Promise<AppointmentMessage[]>;
  city(sql: TransactionSql, userId: string): Promise<string>;
}
export interface DetectedAppointment {
  title: string;
  cityId: string;
  cityName: string;
  timeZone: string;
  placeName: string;
  localStartsAt: string;
  timeReferenceMessageId: string;
  relativeDay?: number | undefined;
  durationMinutes: number;
  evidence: { messageId: string; version: number }[];
  replacesAppointmentId?: string | undefined;
}
export interface AppointmentGenerationContext {
  serviceFundedRetry?: boolean;
  recoveryAttempt?: number;
  paragraphScenes?: boolean;
  userId: string;
  operationId: string;
  appointment: Appointment;
  character: AppointmentCharacter;
  session: AppointmentSession;
  action: { input: string; custom: boolean; finish: boolean } | null;
}
export interface AppointmentNarrative {
  detect(input: {
    userId: string;
    operationId: string;
    character: AppointmentCharacter;
    messages: AppointmentMessage[];
    serverNow: string;
    existing: Appointment[];
  }): Promise<DetectedAppointment | null>;
  generate(
    input: AppointmentGenerationContext,
  ): Promise<{ block: AppointmentBlock; outcome: string }>;
  review(input: AppointmentGenerationContext): Promise<AppointmentReview>;
}
/** Social signals are reviewed evidence; the settlement service owns the deterministic projection. */
export interface AppointmentReview {
  reflection: string;
  signals: {
    type: "warmth" | "respect" | "support" | "disrespect" | "pressure";
    evidenceDecisionIds: string[];
    reason: string;
  }[];
  memories: { content: string; evidenceBlockIds: string[] }[];
  /** Same dimensions and ranges as DomainKit.RelationshipSignal; never an affinity score. */
  relationshipSignal?: {
    warmth: number;
    responsiveness: number;
    respect: number;
    empathy: number;
    reciprocity: number;
    disclosure: number;
    resonance: number;
    engagement: number;
    boundaryHarm: number;
    repair: number;
    significance: number;
    confidence: number;
    reasonZh: string;
  };
}
export interface AppointmentService {
  list(userId: string): Promise<{ appointments: Appointment[]; serverNow: string }>;
  detect(
    userId: string,
    input: { characterId: string; conversationId: string },
  ): Promise<{ appointments: Appointment[]; serverNow: string }>;
  detail(userId: string, id: string): Promise<AppointmentDetail>;
  start(
    userId: string,
    id: string,
    input: AppointmentCommand,
    paragraphScenes?: boolean,
  ): Promise<AppointmentDetail>;
  choose(
    userId: string,
    id: string,
    input: AppointmentChoice,
    paragraphScenes?: boolean,
  ): Promise<AppointmentDetail>;
  cancel(
    userId: string,
    id: string,
    input: AppointmentCommand,
  ): Promise<AppointmentDetail>;
}
export interface AppointmentSettlementSeed {
  eventId: string;
  settlementAt: string;
  characterVersion: number;
  relationship: Record<string, unknown> | null;
  review: AppointmentReview;
  settled: boolean;
}
export interface AppointmentSettlementWriter {
  readMemory?(
    sql: TransactionSql,
    userId: string,
    id: string,
  ): Promise<{ payload: unknown; deletedAt: string | null } | undefined>;
  character(
    sql: TransactionSql,
    userId: string,
    id: string,
  ): Promise<
    { version: number; payload: unknown; deletedAt: string | null } | undefined
  >;
  relationship(
    sql: TransactionSql,
    userId: string,
    characterId: string,
    expectedVersion: number,
    relationship: Record<string, unknown>,
    commandId: string,
  ): Promise<unknown>;
  memory(
    sql: TransactionSql,
    userId: string,
    characterId: string,
    memoryId: string,
    content: string,
    appointmentId: string,
    commandId: string,
    evidence?: string,
    eventDate?: string,
  ): Promise<void>;
}
