import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { createHash } from "node:crypto";
import { join } from "node:path";

// All planning, generation and review share one durable admission ledger.
// Interrupted/unknown-cost attempts retain their upper bound; never assume free.
export function createLibraryProvider(
  output,
  {
    capCNY = 35,
    fetcher = fetch,
    reasoningEffort = "minimal",
    model = "z-ai/glm-5.3-flash",
    promptPriceCeiling = 0.2,
    completionPriceCeiling = 0.6,
    preferredProviders = ["Parasail"],
    responseSchema,
    providerName = "openrouter",
    timeoutMs = 240000,
  } = {},
) {
  if (!(Number.isFinite(capCNY) && capCNY > 0))
    throw Error("Library budget must be finite and positive");
  if (!["openrouter", "openai"].includes(providerName))
    throw Error("Unsupported library provider");
  mkdirSync(output, { recursive: true });
  const ledgerPath = join(output, "ledger.jsonl");
  const rows = existsSync(ledgerPath)
    ? readFileSync(ledgerPath, "utf8")
        .split("\n")
        .filter(Boolean)
        .map(JSON.parse)
    : [];
  const costs = new Map();
  for (const row of rows) {
    if (row.kind === "dispatch") costs.set(row.key, row.upperUSD);
    if (
      row.kind === "receipt" &&
      Number.isFinite(row.costUSD) &&
      row.costUSD >= 0
    )
      costs.set(row.key, row.costUSD);
  }
  const accountedCNY = () =>
    [...costs.values()].reduce((a, b) => a + b, 0) * 7.2;
  const log = (row) =>
    appendFileSync(
      ledgerPath,
      JSON.stringify({ at: new Date().toISOString(), ...row }) + "\n",
    );
  async function request(key, system, data, maxTokens = 14000) {
    if (!/^[a-z0-9-]+$/.test(key)) throw Error("Invalid receipt key");
    const chatBody = {
      model,
      messages: [
        { role: "system", content: system },
        { role: "user", content: JSON.stringify(data) },
      ],
      max_tokens: maxTokens,
      temperature: 0.65,
      reasoning: { effort: reasoningEffort },
      response_format:
        responseSchema && providerName === "openrouter"
          ? {
              type: "json_schema",
              json_schema: {
                name: "authored_content",
                strict: true,
                schema: responseSchema,
              },
            }
          : { type: "json_object" },
      ...(providerName === "openrouter"
        ? {
            provider: {
              ...(preferredProviders.length
                ? { order: preferredProviders }
                : {}),
              allow_fallbacks: true,
              require_parameters: true,
              max_price: {
                prompt: promptPriceCeiling,
                completion: completionPriceCeiling,
              },
            },
          }
        : {}),
      user: "lingotrip-offline-library-20260911",
    };
    const body =
      providerName === "openai"
        ? {
            model,
            store: false,
            instructions: system,
            input: JSON.stringify(data),
            max_output_tokens: maxTokens,
            reasoning: { effort: reasoningEffort },
            text: {
              format: responseSchema
                ? {
                    type: "json_schema",
                    name: "authored_content",
                    strict: true,
                    schema: responseSchema,
                  }
                : { type: "json_object" },
            },
          }
        : chatBody;
    const serialized = JSON.stringify(body);
    const hash = createHash("sha256").update(serialized).digest("hex");
    const requestPath = join(output, key + ".request.json");
    const responsePath = join(output, key + ".response.json");
    if (costs.has(key)) {
      if (
        !existsSync(requestPath) ||
        createHash("sha256").update(readFileSync(requestPath)).digest("hex") !==
          hash
      )
        throw Error("Previously dispatched input changed: " + key);
      if (!existsSync(responsePath))
        throw Error(
          "Unresolved paid attempt; manual reconciliation required: " + key,
        );
      return decode(
        JSON.parse(readFileSync(responsePath, "utf8")),
        providerName,
      );
    }
    const upperUSD =
      ((Buffer.byteLength(serialized) * promptPriceCeiling +
        maxTokens * completionPriceCeiling) /
        1e6) *
      1.1;
    if (accountedCNY() + upperUSD * 7.2 > capCNY)
      throw Error(`CNY ${capCNY} library budget exhausted`);
    const apiKey =
      providerName === "openai"
        ? process.env.OPENAI_API_KEY
        : process.env.OPENROUTER_API_KEY;
    if (!apiKey) throw Error("Server-side provider key required");
    writeFileSync(requestPath, serialized);
    costs.set(key, upperUSD);
    log({ kind: "dispatch", key, hash, upperUSD });
    const started = Date.now();
    const endpoint =
      providerName === "openai"
        ? "https://api.openai.com/v1/responses"
        : "https://openrouter.ai/api/v1/chat/completions";
    const response = await fetcher(endpoint, {
      method: "POST",
      headers: {
        authorization: `Bearer ${apiKey}`,
        "content-type": "application/json",
      },
      body: serialized,
      signal: AbortSignal.timeout(timeoutMs),
    });
    const raw = await response.text();
    writeFileSync(responsePath, raw);
    const envelope = JSON.parse(raw);
    const measuredCost =
      Number.isFinite(envelope.usage?.cost) && envelope.usage.cost >= 0;
    const inputTokens =
      envelope.usage?.input_tokens ?? envelope.usage?.prompt_tokens;
    const outputTokens =
      envelope.usage?.output_tokens ?? envelope.usage?.completion_tokens;
    const usageBound =
      providerName !== "openrouter" &&
      Number.isFinite(inputTokens) &&
      Number.isFinite(outputTokens)
        ? (inputTokens * promptPriceCeiling +
            outputTokens * completionPriceCeiling) /
          1e6
        : null;
    const costUSD = measuredCost ? envelope.usage.cost : usageBound;
    if (costUSD !== null) costs.set(key, costUSD);
    log({
      kind: "receipt",
      key,
      status: response.status,
      ms: Date.now() - started,
      costUSD,
      costBasis: measuredCost
        ? "provider-receipt"
        : usageBound === null
          ? "reserved-upper-bound"
          : "usage-at-price-ceiling",
      usage: envelope.usage ?? null,
      provider: envelope.provider ?? providerName,
      requestId: envelope.id,
    });
    return decode(envelope, providerName);
  }
  return { request, accountedCNY };
}

function decode(envelope, providerName) {
  if (envelope.error)
    throw Error("Provider request failed: " + String(envelope.error.code));
  if (providerName === "openai") {
    if (envelope.status !== "completed")
      throw Error("Incomplete provider output");
    const text = (envelope.output ?? [])
      .flatMap((item) => item.content ?? [])
      .filter((item) => item.type === "output_text")
      .map((item) => item.text)
      .join("");
    return JSON.parse(text);
  }
  if (envelope.choices?.[0]?.finish_reason !== "stop")
    throw Error("Incomplete provider output");
  const text = envelope.choices[0].message.content.trim();
  const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/.exec(text);
  return JSON.parse(fenced ? fenced[1] : text);
}
