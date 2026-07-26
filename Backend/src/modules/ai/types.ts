export type AiMessage = Readonly<{
  content: string;
  role: "assistant" | "system" | "user";
}>;

export type AiResponseFormat = "json_object" | "text";

export type AiRouteConfig = Readonly<{
  allowJsonResponse: boolean;
  configVersion: number;
  maxInputCharacters: number;
  maxMessages: number;
  maxOutputTokens: number;
  model: string;
  provider: "deepseek" | "openai" | "anthropic" | "google";
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
  provider: "deepseek" | "openai" | "anthropic" | "google";
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
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
}>;

export type AiCompletion = Readonly<{
  content: string;
  model: string;
  providerRequestId: string | null;
  usage: AiUsage;
}>;

export type AiProviderRequest = Readonly<{
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
