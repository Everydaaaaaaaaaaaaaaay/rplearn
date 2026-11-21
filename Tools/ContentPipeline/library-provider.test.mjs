import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createLibraryProvider } from "./library-provider.mjs";

test("receipts survive resume, replay is free and changed inputs cannot reuse IDs", async () => {
  const dir = mkdtempSync(join(tmpdir(), "npc-budget-"));
  const previous = process.env.OPENROUTER_API_KEY;
  process.env.OPENROUTER_API_KEY = "test-only";
  let calls = 0;
  const fetcher = async () => {
    calls++;
    return new Response(
      JSON.stringify({
        usage: { cost: 0.001 },
        choices: [
          {
            finish_reason: "stop",
            message: { content: '```json\n{"ok":true}\n```' },
          },
        ],
      }),
    );
  };
  try {
    const first = createLibraryProvider(dir, { fetcher });
    assert.deepEqual(await first.request("one", "system", { x: 1 }), {
      ok: true,
    });
    const resumed = createLibraryProvider(dir, { fetcher });
    assert.ok(Math.abs(resumed.accountedCNY() - 0.0072) < 1e-12);
    await resumed.request("one", "system", { x: 1 });
    assert.equal(calls, 1);
    await assert.rejects(
      resumed.request("one", "changed", { x: 1 }),
      /input changed/,
    );
    assert.equal(
      readFileSync(join(dir, "ledger.jsonl"), "utf8").includes("test-only"),
      false,
    );
  } finally {
    if (previous === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = previous;
    rmSync(dir, { recursive: true });
  }
});

test("interrupted attempts stay reserved and cannot silently redispatch", async () => {
  const dir = mkdtempSync(join(tmpdir(), "npc-budget-"));
  const previous = process.env.OPENROUTER_API_KEY;
  process.env.OPENROUTER_API_KEY = "test-only";
  let calls = 0;
  const fetcher = async () => {
    calls++;
    throw Error("connection lost");
  };
  try {
    const first = createLibraryProvider(dir, { fetcher });
    await assert.rejects(first.request("one", "system", {}), /connection lost/);
    const resumed = createLibraryProvider(dir, { fetcher });
    assert.ok(resumed.accountedCNY() > 0);
    await assert.rejects(
      resumed.request("one", "system", {}),
      /manual reconciliation/,
    );
    assert.equal(calls, 1);
    const capped = createLibraryProvider(dir, { fetcher, capCNY: 0.001 });
    await assert.rejects(
      capped.request("two", "system", {}),
      /budget exhausted/,
    );
    assert.equal(calls, 1);
  } finally {
    if (previous === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = previous;
    rmSync(dir, { recursive: true });
  }
});

test("structured response contracts are persisted with the dispatched request", async () => {
  const dir = mkdtempSync(join(tmpdir(), "npc-contract-"));
  const previous = process.env.OPENROUTER_API_KEY;
  process.env.OPENROUTER_API_KEY = "test-only";
  const schema = {
    type: "object",
    properties: { ok: { type: "boolean" } },
    required: ["ok"],
    additionalProperties: false,
  };
  try {
    const provider = createLibraryProvider(dir, {
      responseSchema: schema,
      fetcher: async (_url, options) => {
        const request = JSON.parse(options.body);
        assert.deepEqual(request.response_format.json_schema.schema, schema);
        return new Response(
          JSON.stringify({
            usage: { cost: 0 },
            choices: [
              { finish_reason: "stop", message: { content: '{"ok":true}' } },
            ],
          }),
        );
      },
    });
    await provider.request("contract", "system", {});
    assert.equal(
      JSON.parse(readFileSync(join(dir, "contract.request.json")))
        .response_format.type,
      "json_schema",
    );
  } finally {
    if (previous === undefined) delete process.env.OPENROUTER_API_KEY;
    else process.env.OPENROUTER_API_KEY = previous;
    rmSync(dir, { recursive: true });
  }
});

test("OpenAI Responses preserves the schema, completed status and token accounting on resume", async () => {
  const dir = mkdtempSync(join(tmpdir(), "npc-openai-provider-"));
  const previous = process.env.OPENAI_API_KEY;
  process.env.OPENAI_API_KEY = "openai-test-only";
  const schema = {
    type: "object",
    properties: { ok: { type: "boolean" } },
    required: ["ok"],
    additionalProperties: false,
  };
  let calls = 0;
  const options = {
    providerName: "openai",
    model: "gpt-5.4-mini",
    reasoningEffort: "low",
    responseSchema: schema,
    promptPriceCeiling: 1,
    completionPriceCeiling: 2,
    fetcher: async (url, request) => {
      calls++;
      assert.equal(url, "https://api.openai.com/v1/responses");
      const body = JSON.parse(request.body);
      assert.equal(body.store, false);
      assert.equal(body.instructions, "system");
      assert.equal(body.input, '{"x":1}');
      assert.deepEqual(body.text.format.schema, schema);
      assert.equal(body.reasoning.effort, "low");
      return new Response(
        JSON.stringify({
          status: "completed",
          usage: { input_tokens: 100, output_tokens: 200 },
          output: [
            {
              type: "message",
              content: [{ type: "output_text", text: '{"ok":true}' }],
            },
          ],
        }),
      );
    },
  };
  try {
    assert.deepEqual(
      await createLibraryProvider(dir, options).request("openai", "system", {
        x: 1,
      }),
      { ok: true },
    );
    const resumed = createLibraryProvider(dir, options);
    assert.deepEqual(await resumed.request("openai", "system", { x: 1 }), {
      ok: true,
    });
    assert.equal(calls, 1);
    assert.ok(Math.abs(resumed.accountedCNY() - 0.0036) < 1e-12);
    assert.equal(
      readFileSync(join(dir, "ledger.jsonl"), "utf8").includes(
        "openai-test-only",
      ),
      false,
    );
  } finally {
    if (previous === undefined) delete process.env.OPENAI_API_KEY;
    else process.env.OPENAI_API_KEY = previous;
    rmSync(dir, { recursive: true });
  }
});

test("admission keeps the legacy default and accepts a task-specific finite budget", () => {
  const dir = mkdtempSync(join(tmpdir(), "npc-authorized-cap-"));
  try {
    assert.doesNotThrow(() => createLibraryProvider(dir, { capCNY: 35 }));
    assert.doesNotThrow(() => createLibraryProvider(dir, { capCNY: 80 }));
    for (const capCNY of [Infinity, NaN, 0, -1]) {
      assert.throws(
        () => createLibraryProvider(dir, { capCNY }),
        /finite and positive/,
      );
    }
  } finally {
    rmSync(dir, { recursive: true });
  }
});
