import { appendFileSync, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { join } from 'node:path';

// All planning, generation and review share one durable admission ledger.
// Interrupted/unknown-cost attempts retain their upper bound; never assume free.
export function createLibraryProvider(output, { capCNY = 25, fetcher = fetch, reasoningEffort = 'minimal', model = 'z-ai/glm-5.3-flash', promptPriceCeiling = 0.2, completionPriceCeiling = 0.6, preferredProviders = ['Parasail'] } = {}) {
  if (!(capCNY > 0 && capCNY <= 25)) throw Error('Library budget must be within CNY 25');
  mkdirSync(output, { recursive: true });
  const ledgerPath = join(output, 'ledger.jsonl');
  const rows = existsSync(ledgerPath) ? readFileSync(ledgerPath, 'utf8').split('\n').filter(Boolean).map(JSON.parse) : [];
  const costs = new Map();
  for (const row of rows) {
    if (row.kind === 'dispatch') costs.set(row.key, row.upperUSD);
    if (row.kind === 'receipt' && Number.isFinite(row.costUSD) && row.costUSD >= 0) costs.set(row.key, row.costUSD);
  }
  const accountedCNY = () => [...costs.values()].reduce((a, b) => a + b, 0) * 7.2;
  const log = row => appendFileSync(ledgerPath, JSON.stringify({ at: new Date().toISOString(), ...row }) + '\n');
  async function request(key, system, data, maxTokens = 14000) {
    if (!/^[a-z0-9-]+$/.test(key)) throw Error('Invalid receipt key');
    const body = {
      model, messages: [{ role: 'system', content: system }, { role: 'user', content: JSON.stringify(data) }],
      max_tokens: maxTokens, temperature: 0.65, reasoning: { effort: reasoningEffort }, response_format: { type: 'json_object' },
      provider: { ...(preferredProviders.length ? {order: preferredProviders} : {}), allow_fallbacks: true, require_parameters: true, max_price: { prompt: promptPriceCeiling, completion: completionPriceCeiling } },
      user: 'lingotrip-offline-library-20260911',
    };
    const serialized = JSON.stringify(body);
    const hash = createHash('sha256').update(serialized).digest('hex');
    const requestPath = join(output, key + '.request.json');
    const responsePath = join(output, key + '.response.json');
    if (costs.has(key)) {
      if (!existsSync(requestPath) || createHash('sha256').update(readFileSync(requestPath)).digest('hex') !== hash) throw Error('Previously dispatched input changed: ' + key);
      if (!existsSync(responsePath)) throw Error('Unresolved paid attempt; manual reconciliation required: ' + key);
      return decode(JSON.parse(readFileSync(responsePath, 'utf8')));
    }
    const upperUSD = (Buffer.byteLength(serialized) * promptPriceCeiling + maxTokens * completionPriceCeiling) / 1e6 * 1.1;
    if (accountedCNY() + upperUSD * 7.2 > capCNY) throw Error('CNY 25 library budget exhausted');
    if (!process.env.OPENROUTER_API_KEY) throw Error('Server-side provider key required');
    writeFileSync(requestPath, serialized);
    costs.set(key, upperUSD);
    log({ kind: 'dispatch', key, hash, upperUSD });
    const started = Date.now();
    const response = await fetcher('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST', headers: { authorization: `Bearer ${process.env.OPENROUTER_API_KEY}`, 'content-type': 'application/json' },
      body: serialized, signal: AbortSignal.timeout(240000),
    });
    const raw = await response.text();
    writeFileSync(responsePath, raw);
    const envelope = JSON.parse(raw);
    const costUSD = Number.isFinite(envelope.usage?.cost) && envelope.usage.cost >= 0 ? envelope.usage.cost : null;
    if (costUSD !== null) costs.set(key, costUSD);
    log({ kind: 'receipt', key, status: response.status, ms: Date.now() - started, costUSD, usage: envelope.usage ?? null, provider: envelope.provider, requestId: envelope.id });
    return decode(envelope);
  }
  return { request, accountedCNY };
}

function decode(envelope) {
  if (envelope.error) throw Error('Provider request failed: ' + String(envelope.error.code));
  if (envelope.choices?.[0]?.finish_reason !== 'stop') throw Error('Incomplete provider output');
  const text = envelope.choices[0].message.content.trim();
  const fenced = /^```(?:json)?\s*([\s\S]*?)\s*```$/.exec(text);
  return JSON.parse(fenced ? fenced[1] : text);
}
