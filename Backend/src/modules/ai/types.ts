export type AiMessage = Readonly<{
  content: string;
  role: "assistant" | "system" | "user";
}>;

export type AiResponseFormat = "json_object" | "text";

export type AiProvider = "anthropic" | "deepseek" | "google" | "openai" | "openrouter";

export type AiRouteConfig = Readonly<{
  allowJsonResponse: boolean;
  configVersion: number;
  maxInputCharacters: number;
  maxMessages: number;
  maxOutputTokens: number;
  model: string;
  provider: AiProvider;
  providerOptions: Readonly<Record<string, unknown>>;
  task: string;
  temperature: number | null;
  timeoutMs: number;
}>;

export type AiRouteSettings = Readonly<{
  allowJsonResponse: boolean;
  enabled: boolean;
  maxInputCharacters: number;
  maxMessages: number;
  maxOutputTokens: number;
  model: string;
  provider: AiProvider;
  providerOptions: Readonly<Record<string, unknown>>;
  temperature: number | null;
  timeoutMs: number;
}>;

export type AiManagedRoute = AiRouteSettings &
  Readonly<{
    configVersion: number;
    task: string;
    updatedAt: string;
  }>;

export type AiRouteRevision = Readonly<{
  changedAt: string;
  changeReason: string;
  configVersion: number;
  operatorKeyId: string;
  settings: AiRouteSettings;
}>;

export type AiUsage = Readonly<{
  cacheHitTokens?: number;
  cacheMissTokens?: number;
  inputTokens: number;
  outputTokens: number;
  providerCostUsd?: string;
  totalTokens: number;
}>;

export type AiProviderClient = Readonly<{
  complete: (request: AiProviderRequest) => Promise<AiCompletion>;
  configured: boolean;
  stream: (request: AiProviderRequest) => Promise<AsyncIterable<AiProviderStreamEvent>>;
}>;

export type AiCompletion = Readonly<{
  finishReason?: string;
  content: string;
  model: string;
  providerRequestId: string | null;
  usage: AiUsage;
}>;

export type AiProviderRequest = Readonly<{
  onAttempt?: () => Promise<void>;
  maxAttempts?: number;
  maxOutputTokens: number;
  messages: readonly AiMessage[];
  responseFormat: AiResponseFormat;
  route: AiRouteConfig;
  signal?: AbortSignal;
  userReference: string;
}>;

export type AiProviderStreamEvent =
  | Readonly<{ text: string; type: "delta" }>
  | Readonly<{ usage: AiUsage; type: "usage" }>
  | Readonly<{
      model: string;
      providerRequestId: string | null;
      type: "metadata";
    }>
  | Readonly<{ type: "done" }>;
