import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { createDatabase, type DatabaseResource } from "../../src/db/client.js";
import { runMigrations } from "../../src/db/migrate.js";
import { integrationConfig } from "../helpers/integration.js";
import { SharedGrammarRepository } from "../../src/modules/grammar/repository.js";
import { loadGrammarSeed } from "../../src/modules/grammar/seed.js";
import { patternIdentity } from "../../src/modules/grammar/identity.js";
import type { GrammarProposal } from "../../src/modules/grammar/types.js";
import { createJobPayloadCipher } from "../../src/modules/jobs/crypto.js";
import { GRAMMAR_LIBRARY_REVIEW_JOB } from "../../src/modules/jobs/types.js";
import { createGrammarService } from "../../src/modules/grammar/service.js";

describe.runIf(process.env.RUN_INTEGRATION_TESTS === "true")(
  "shared grammar database concurrency",
  () => {
    let db: DatabaseResource;
    let repo: SharedGrammarRepository;
    const proposal: GrammarProposal = {
      identity: "emphatic-do",
      title: "do强调肯定动作",
      explanationZh: "do 加动词原形强调动作。",
      triggers: ["do"],
      examples: [{ en: "I do enjoy music.", zh: "我确实喜欢音乐。" }],
      patterns: [{ steps: ["do", "<word>"], maximumGaps: [0] }],
    };
    beforeAll(async () => {
      db = createDatabase(integrationConfig(process.env));
      await runMigrations(db);
      repo = new SharedGrammarRepository(db, await loadGrammarSeed());
    });
    afterAll(async () => {
      await db.close();
    });
    it("concurrent equivalent descriptions publish exactly one canonical rule", async () => {
      const snapshot = await repo.snapshot();
      const fingerprint = patternIdentity(proposal);
      const input = {
        snapshotRevision: snapshot.revision,
        fingerprint,
        proposal,
        decision: {
          verdict: "distinct" as const,
          existingId: null,
          identity: proposal.identity,
        },
      };
      const ids = await Promise.all(
        Array.from({ length: 12 }, (_, i) =>
          repo.reconcile({
            ...input,
            proposal: { ...proposal, title: `同一规则的描述${String(i)}` },
          }),
        ),
      );
      expect(new Set(ids).size).toBe(1);
      expect(
        (await repo.snapshot()).points.filter((p) => p.id.startsWith("shared-")).length,
      ).toBe(1);
    });
    it("a semantically equivalent proposal resolves to a bundled ID without adding a rule", async () => {
      const other = {
        ...proposal,
        identity: "completed-action-tense",
        patterns: [{ steps: ["have|has", "<past-participle>"], maximumGaps: [1] }],
      };
      const snapshot = await repo.snapshot();
      const result = await repo.reconcile({
        snapshotRevision: snapshot.revision,
        fingerprint: patternIdentity(other),
        proposal: other,
        decision: {
          verdict: "equivalent",
          existingId: "present-perfect",
          identity: null,
        },
      });
      expect(result).toBe("present-perfect");
      expect((await repo.snapshot()).points.length).toBe(snapshot.points.length);
    });
    it("a catalog change during independent review quarantines rather than duplicates a concept", async () => {
      const other = {
        ...proposal,
        identity: "another-description-of-emphasis",
        patterns: [{ steps: ["does", "<word>"], maximumGaps: [0] }],
      };
      expect(
        await repo.reconcile({
          snapshotRevision: "stale",
          fingerprint: patternIdentity(other),
          proposal: other,
          decision: { verdict: "distinct", existingId: null, identity: other.identity },
        }),
      ).toBeNull();
      expect(await repo.resolution(patternIdentity(other))).toBeNull();
    });
    it("concurrent misses transactionally schedule only one durable review job", async () => {
      const candidate = {
        ...proposal,
        identity: "emphatic-did",
        patterns: [{ steps: ["did", "<word>"], maximumGaps: [0] }],
      };
      const fingerprint = patternIdentity(candidate);
      const cipher = createJobPayloadCipher(integrationConfig(process.env));
      await Promise.all(
        Array.from({ length: 12 }, () =>
          repo.schedule(fingerprint, candidate, () =>
            cipher.prepare(
              GRAMMAR_LIBRARY_REVIEW_JOB,
              { proposal: candidate },
              { uniqueKey: `grammar-review:${fingerprint}` },
            ),
          ),
        ),
      );
      const [row] = await db.sql<
        { count: string }[]
      >`select count(*)::text as count from app.jobs where unique_key = ${`grammar-review:${fingerprint}`}`;
      expect(row?.count).toBe("1");
      const snapshot = await repo.snapshot();
      expect(
        await repo.reconcile({
          snapshotRevision: snapshot.revision,
          fingerprint,
          proposal: candidate,
          decision: { verdict: "equivalent", existingId: "modal-verb", identity: null },
        }),
      ).toBe("modal-verb");
    });
    it("analysis queues a generic proposal, independent review publishes it, and the catalog reuses it", async () => {
      const candidate = {
        ...proposal,
        identity: "lest-purpose-clause",
        title: "lest引导目的从句",
        triggers: ["lest"],
        examples: [
          { en: "Speak quietly lest anyone hear us.", zh: "小声说话，以免别人听见。" },
        ],
        patterns: [{ steps: ["lest", "<word>"], maximumGaps: [0] }],
      };
      const config = integrationConfig(process.env),
        cipher = createJobPayloadCipher(config);
      const operationId = "019c0123-4567-789a-8bcd-ef01234567f1";
      // Test-only actor in the isolated database; no email or external notification.
      await db.sql`insert into app.users(id) values (${operationId}) on conflict do nothing`;
      const user = { id: operationId };
      const service = createGrammarService(
        repo,
        {
          complete: (_userId, input) =>
            Promise.resolve({
              content:
                input.task === "grammar_analysis"
                  ? JSON.stringify({
                      summaryZh: "目的从句",
                      points: [
                        {
                          title: candidate.title,
                          quote: "lest anyone",
                          pattern: "lest + clause",
                          explanationZh: "这里表示避免某事发生。",
                          learnerTipZh: "用于较正式的语境。",
                          canonicalPointId: null,
                          proposal: candidate,
                        },
                      ],
                    })
                  : JSON.stringify({
                      verdict: "distinct",
                      existingId: null,
                      identity: candidate.identity,
                    }),
              model: "mock",
              requestId: "workflow",
              usage: null,
            }),
        },
        cipher,
      );
      await service.analyze(user.id, {
        sentence: "Go slowly lest anyone fall.",
        learnerLevel: "B2",
        operationId,
      });
      const [job] = await db.sql<
        {
          type: string;
          key_version: string;
          payload_ciphertext: Buffer;
          nonce: Buffer;
          tag: Buffer;
        }[]
      >`
      select type,key_version,payload_ciphertext,nonce,tag from app.jobs where unique_key = ${`grammar-review:${patternIdentity(candidate)}`}`;
      if (job === undefined) throw new Error("Review not durably queued");
      await service.curate(
        cipher.open({
          ...job,
          keyVersion: job.key_version,
          payloadCiphertext: job.payload_ciphertext,
        }),
      );
      const stored = (await service.catalog()).points.filter(
        (p) => p.title === candidate.title,
      );
      expect(stored).toHaveLength(1);
      expect(await repo.resolution(patternIdentity(candidate))).toBe(stored[0]?.id);
      const again = await service.analyze(user.id, {
        sentence: "Go slowly lest anyone fall.",
        learnerLevel: "B2",
        operationId,
      });
      expect(again.analysis.points[0]?.canonicalPointId).toBe(stored[0]?.id);
      expect(again.learnedPoints).toHaveLength(1);
    });
  },
);
