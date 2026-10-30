import { describe, expect, it, vi } from "vitest";
import { createGrammarService } from "../../../src/modules/grammar/service.js";
import { loadGrammarSeed } from "../../../src/modules/grammar/seed.js";
import {
  patternIdentity,
  proposalIsSafe,
} from "../../../src/modules/grammar/identity.js";
import type {
  GrammarRepository,
  GrammarProposal,
} from "../../../src/modules/grammar/types.js";
import type { JobPayloadCipher } from "../../../src/modules/jobs/crypto.js";
import type { AiService } from "../../../src/modules/ai/service.js";

const proposal: GrammarProposal = {
  identity: "emphatic-do",
  title: "do 强调肯定动作",
  explanationZh: "在肯定句中用 do 加动词原形强调动作。",
  triggers: ["do"],
  examples: [{ en: "I do enjoy music.", zh: "我确实喜欢音乐。" }],
  patterns: [{ steps: ["do", "<word>"], maximumGaps: [0] }],
};
const sentence = "I do love this book.";
const point = {
  title: proposal.title,
  quote: "do love",
  pattern: "do + verb",
  explanationZh: "这里强调喜欢的动作。",
  learnerTipZh: "do 后仍用动词原形。",
  canonicalPointId: null,
  proposal,
};
const operationId = "019c0123-4567-789a-8bcd-ef01234567f0";
function setup(raw = { summaryZh: "用 do 强调肯定动作。", points: [point] }) {
  const repository: GrammarRepository = {
    snapshot: vi.fn(() => Promise.resolve({ revision: "v1", points: [] })),
    resolution: vi.fn(() => Promise.resolve(undefined)),
    schedule: vi.fn(() => Promise.resolve()),
    reconcile: vi.fn(() => Promise.resolve("shared-point")),
  };
  const complete = vi.fn<AiService["complete"]>(() =>
    Promise.resolve({
      content: JSON.stringify(raw),
      model: "mock",
      requestId: "1",
      usage: null,
    }),
  );
  const cipher = {
    prepare: vi.fn((...args: unknown[]) => args),
  } as unknown as JobPayloadCipher;
  return {
    repository,
    complete,
    cipher,
    service: createGrammarService(repository, { complete }, cipher),
  };
}
describe("shared grammar", () => {
  it("keeps the complete bundled baseline without inventing extra IDs", async () => {
    const seed = await loadGrammarSeed();
    expect(seed).toHaveLength(100);
    expect(seed.find((p) => p.id === "as-as")?.patterns[0]?.maximumGaps).toEqual([8]);
  });
  it("returns analysis immediately and schedules only generic content for independent review", async () => {
    const { service, repository, cipher, complete } = setup();
    const result = await service.analyze(operationId, {
      sentence,
      learnerLevel: "B1",
      operationId,
    });
    expect(result.analysis.points).toHaveLength(1);
    expect(complete).toHaveBeenCalledTimes(1);
    expect(repository.schedule).toHaveBeenCalledOnce();
    const prepare = vi.mocked(repository.schedule).mock.calls[0]?.[2];
    prepare?.();
    const payload = vi.mocked(cipher.prepare).mock.calls[0]?.[1];
    expect(JSON.stringify(payload)).not.toContain(sentence);
    expect(payload).toMatchObject({ proposal, userId: operationId });
  });
  it("different Chinese descriptions reuse an existing canonical concept", async () => {
    const { service, repository } = setup();
    vi.mocked(repository.resolution).mockResolvedValue("present-perfect");
    const result = await service.analyze(operationId, {
      sentence,
      learnerLevel: "B1",
      operationId,
    });
    expect(result.analysis.points[0]?.canonicalPointId).toBe("present-perfect");
    expect(repository.schedule).not.toHaveBeenCalled();
  });
  it("uses structural identity independent of title and alternative ordering", () => {
    const renamed = { ...proposal, title: "强调句的另一种描述" };
    expect(patternIdentity(proposal)).toBe(patternIdentity(renamed));
    expect(
      patternIdentity({
        patterns: [{ steps: ["has|have", "<past-participle>"], maximumGaps: [2] }],
      }),
    ).toBe(
      patternIdentity({
        patterns: [{ steps: ["have|has", "<past-participle>"], maximumGaps: [2] }],
      }),
    );
  });
  it("does not enqueue pending or ambiguous proposals again", async () => {
    const { service, repository } = setup();
    vi.mocked(repository.resolution).mockResolvedValue(null);
    await service.analyze(operationId, { sentence, learnerLevel: "B1", operationId });
    expect(repository.schedule).not.toHaveBeenCalled();
  });
  it("rejects copied private examples and examples that do not demonstrate their patterns", () => {
    expect(
      proposalIsSafe(
        { ...proposal, examples: [{ en: sentence, zh: "原句" }] },
        sentence,
      ),
    ).toBe(false);
    expect(
      proposalIsSafe(
        { ...proposal, examples: [{ en: "Hello world.", zh: "你好" }] },
        sentence,
      ),
    ).toBe(false);
    expect(proposalIsSafe(proposal, sentence)).toBe(true);
  });
  it("deduplicates two descriptions mapped to the same canonical point in one result", async () => {
    const { service, repository } = setup({
      summaryZh: "说明",
      points: [point, { ...point, title: "另一说法" }],
    });
    vi.mocked(repository.resolution).mockResolvedValue("emphatic-do");
    expect(
      (
        await service.analyze(operationId, {
          sentence,
          learnerLevel: "B1",
          operationId,
        })
      ).analysis.points,
    ).toHaveLength(1);
  });
  it("queue or curation failures do not break successful analysis", async () => {
    const { service, repository } = setup();
    vi.mocked(repository.schedule).mockRejectedValue(new Error("queue offline"));
    expect(
      (
        await service.analyze(operationId, {
          sentence,
          learnerLevel: "B1",
          operationId,
        })
      ).analysis.points,
    ).toHaveLength(1);
  });
  it("refuses unrelated quotes rather than saving invented evidence", async () => {
    const { service } = setup({
      summaryZh: "说明",
      points: [{ ...point, quote: "not in the sentence" }],
    });
    await expect(
      service.analyze(operationId, { sentence, learnerLevel: "B1", operationId }),
    ).rejects.toMatchObject({ code: "GRAMMAR_INVALID_OUTPUT" });
  });
  it("typographic apostrophes do not break a valid analysis", async () => {
    const { service } = setup({
      summaryZh: "完成时",
      points: [{ ...point, quote: "I've finished" }],
    });
    expect(
      (
        await service.analyze(operationId, {
          sentence: "I’ve finished.",
          learnerLevel: "B1",
          operationId,
        })
      ).analysis.points,
    ).toHaveLength(1);
  });
  it("invalid sharing metadata does not discard useful sentence analysis", async () => {
    const { service, complete, repository } = setup();
    complete.mockResolvedValue({
      content: JSON.stringify({
        summaryZh: "强调动作",
        points: [{ ...point, proposal: { malformed: true } }],
      }),
      model: "mock",
      requestId: "m",
      usage: null,
    });
    expect(
      (
        await service.analyze(operationId, {
          sentence,
          learnerLevel: "B1",
          operationId,
        })
      ).analysis.points,
    ).toHaveLength(1);
    expect(repository.schedule).not.toHaveBeenCalled();
  });
  it("source names must not leak into generic library examples", () => {
    expect(
      proposalIsSafe(
        { ...proposal, examples: [{ en: "I do know Sarah.", zh: "我确实认识她。" }] },
        "I do visit Sarah.",
      ),
    ).toBe(false);
  });
  it("independent review receives the full current catalog and no private sentence", async () => {
    const { service, complete, repository } = setup();
    vi.mocked(repository.snapshot).mockResolvedValue({
      revision: "v1",
      points: await loadGrammarSeed(),
    });
    vi.mocked(complete).mockResolvedValue({
      content: JSON.stringify({
        verdict: "equivalent",
        existingId: "present-perfect",
        identity: null,
      }),
      model: "mock",
      requestId: "2",
      usage: null,
    });
    await service.curate({
      fingerprint: patternIdentity(proposal),
      proposal,
      userId: operationId,
      parentOperationId: operationId,
    });
    expect(complete.mock.calls[0]?.[1]).toMatchObject({
      task: "grammar_library_review",
    });
    expect(JSON.stringify(complete.mock.calls)).not.toContain(sentence);
    expect(repository.reconcile).toHaveBeenCalledWith(
      expect.objectContaining({
        decision: {
          verdict: "equivalent",
          existingId: "present-perfect",
          identity: null,
        },
      }),
    );
  });
  it("bounds growing catalogs and checks later batches before accepting a new concept", async () => {
    const { service, complete, repository } = setup();
    const seed = (await loadGrammarSeed())[0];
    if (seed === undefined) throw new Error("Missing grammar baseline");
    const points = Array.from({ length: 90 }, (_, i) => ({
      ...seed,
      id: `rule-${String(i)}`,
      explanationZh: "通用语法说明".repeat(180),
    }));
    vi.mocked(repository.snapshot).mockResolvedValue({ revision: "v1", points });
    complete.mockImplementation((_user, input) =>
      Promise.resolve({
        content: JSON.stringify(
          input.task === "grammar_analysis"
            ? { summaryZh: "说明", points: [point] }
            : input.messages[0]?.content.includes('"id":"rule-89"')
              ? { verdict: "equivalent", existingId: "rule-89", identity: null }
              : { verdict: "distinct", existingId: null, identity: proposal.identity },
        ),
        model: "mock",
        requestId: "growing",
        usage: null,
      }),
    );
    await service.analyze(operationId, { sentence, learnerLevel: "B1", operationId });
    expect(
      complete.mock.calls[0]?.[1].messages.reduce((n, m) => n + m.content.length, 0),
    ).toBeLessThan(64_000);
    complete.mockClear();
    await service.curate({
      fingerprint: patternIdentity(proposal),
      proposal,
      userId: operationId,
      parentOperationId: operationId,
    });
    expect(complete.mock.calls.length).toBeGreaterThan(1);
    expect(
      new Set(complete.mock.calls.map(([, input]) => input.operationId)).size,
    ).toBe(complete.mock.calls.length);
    for (const [, input] of complete.mock.calls)
      expect(input.messages.reduce((n, m) => n + m.content.length, 0)).toBeLessThan(
        64_000,
      );
    expect(repository.reconcile).toHaveBeenCalledWith(
      expect.objectContaining({
        decision: { verdict: "equivalent", existingId: "rule-89", identity: null },
      }),
    );
  });
  it("retries a failed independent review with a new operation while keeping each attempt idempotent", async () => {
    const { service, complete } = setup();
    const payload = {
      fingerprint: patternIdentity(proposal),
      proposal,
      userId: operationId,
      parentOperationId: operationId,
    };
    complete.mockRejectedValueOnce(new Error("upstream unavailable"));
    await expect(service.curate(payload, 1)).rejects.toThrow("upstream unavailable");
    complete.mockResolvedValue({
      content: JSON.stringify({
        verdict: "uncertain",
        existingId: null,
        identity: null,
      }),
      model: "mock",
      requestId: "retry",
      usage: null,
    });
    await service.curate(payload, 2);
    await service.curate(payload, 2);
    expect(complete.mock.calls[0]?.[1].operationId).not.toBe(
      complete.mock.calls[1]?.[1].operationId,
    );
    expect(complete.mock.calls[1]?.[1].operationId).toBe(
      complete.mock.calls[2]?.[1].operationId,
    );
  });
});
