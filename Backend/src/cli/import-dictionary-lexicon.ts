import "dotenv/config";
import { createReadStream } from "node:fs";
import { createGunzip } from "node:zlib";
import { createInterface } from "node:readline";
import { z } from "zod";
import { loadConfig } from "../config/env.js";
import { createDatabase } from "../db/client.js";

const schema = z
  .object({
    lemma: z.string().min(1).max(120),
    definition: z.string().max(800),
    meaning: z.string().max(800),
    forms: z.array(z.string()),
    existingExamples: z.array(z.string()).max(2),
    sourceVersion: z.string().regex(/^[a-f0-9]{64}$/),
  })
  .strict();
const path = process.argv[2];
if (!path) throw new Error("Usage: import-dictionary-lexicon PATH.jsonl.gz");
const database = createDatabase(loadConfig());
try {
  let rows: z.infer<typeof schema>[] = [];
  let total = 0;
  const flush = async () => {
    if (rows.length === 0) return;
    const values = rows.map((r) => ({
      lemma: r.lemma,
      definition: r.definition,
      meaning: r.meaning,
      forms: JSON.stringify(r.forms),
      existing_examples: JSON.stringify(r.existingExamples),
      source_version: r.sourceVersion,
    }));
    await database.sql`insert into app.dictionary_example_lexicon ${database.sql(values)}
      on conflict (lemma) do update set definition=excluded.definition,meaning=excluded.meaning,forms=excluded.forms,existing_examples=excluded.existing_examples,source_version=excluded.source_version
      where dictionary_example_lexicon.source_version is distinct from excluded.source_version`;
    total += rows.length;
    rows = [];
  };
  const lines = createInterface({
    input: createReadStream(path).pipe(createGunzip()),
    crlfDelay: Infinity,
  });
  for await (const line of lines) {
    rows.push(schema.parse(JSON.parse(line) as unknown));
    if (rows.length >= 1000) await flush();
  }
  await flush();
  process.stdout.write(
    `Imported lexical baseline: ${String(total)} entries. No user data or generation records removed.\n`,
  );
} finally {
  await database.close();
}
