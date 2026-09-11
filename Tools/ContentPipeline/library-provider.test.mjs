import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createLibraryProvider } from './library-provider.mjs';

test('receipts survive resume, replay is free and changed inputs cannot reuse IDs', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'npc-budget-'));
  const previous = process.env.OPENROUTER_API_KEY;
  process.env.OPENROUTER_API_KEY = 'test-only';
  let calls = 0;
  const fetcher = async () => {
    calls++;
    return new Response(JSON.stringify({ usage: { cost: 0.001 }, choices: [{ finish_reason: 'stop', message: { content: '```json\n{"ok":true}\n```' } }] }));
  };
  try {
    const first = createLibraryProvider(dir, { fetcher });
    assert.deepEqual(await first.request('one', 'system', { x: 1 }), { ok: true });
    const resumed = createLibraryProvider(dir, { fetcher });
    assert.ok(Math.abs(resumed.accountedCNY() - 0.0072) < 1e-12);
    await resumed.request('one', 'system', { x: 1 });
    assert.equal(calls, 1);
    await assert.rejects(resumed.request('one', 'changed', { x: 1 }), /input changed/);
    assert.equal(readFileSync(join(dir, 'ledger.jsonl'), 'utf8').includes('test-only'), false);
  } finally {
    if (previous === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = previous;
    rmSync(dir, { recursive: true });
  }
});

test('interrupted attempts stay reserved and cannot silently redispatch', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'npc-budget-'));
  const previous = process.env.OPENROUTER_API_KEY;
  process.env.OPENROUTER_API_KEY = 'test-only';
  let calls = 0;
  const fetcher = async () => { calls++; throw Error('connection lost'); };
  try {
    const first = createLibraryProvider(dir, { fetcher });
    await assert.rejects(first.request('one', 'system', {}), /connection lost/);
    const resumed = createLibraryProvider(dir, { fetcher });
    assert.ok(resumed.accountedCNY() > 0);
    await assert.rejects(resumed.request('one', 'system', {}), /manual reconciliation/);
    assert.equal(calls, 1);
    const capped = createLibraryProvider(dir, { fetcher, capCNY: 0.001 });
    await assert.rejects(capped.request('two', 'system', {}), /budget exhausted/);
    assert.equal(calls, 1);
  } finally {
    if (previous === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = previous;
    rmSync(dir, { recursive: true });
  }
});
