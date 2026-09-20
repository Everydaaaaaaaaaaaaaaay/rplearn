# Original learner examples, version 1

2026-09-20: 40 high-frequency function words, 80 original English examples. These
were authored and reviewed by the coding assistant, not copied from a dictionary,
film or corpus and not represented as human-reviewed material. This is a bounded
first batch, not a claim that all 5,000 frequent words now have examples.

`examples.tsv` contains headword, part of speech, contextual English definition,
and example. Review checks: target word appears as a complete token, ordinary
English grammar, definition agrees with use, natural everyday context, no factual
claims requiring verification. Formal `whom` examples are explicitly labelled.
Each word has two examples; words with one central use get varied contexts.
Chinese translations use the existing shared LLM translation/cache flow.

`apply.py` inserts/upserts only this source's reserved negative sense ranks into
the bundled **build artifact**, retaining original WordNet rows. It also runs from
`build_dictionary.py`. Negative ranks identify `lingotrip-learner-examples/v1` in
App requests, so these are never attributed to WordNet. Keep existing row order
and IDs stable; bump source version if identities must change in a future batch.

```
python3 Tools/Dictionary/LearnerExamples/apply.py App/Resources/learner_dictionary.sqlite
python3 Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py self-test
python3 Tools/Dictionary/ExampleTranslationSeed/seed_pipeline.py stats
```

Display policy: prefer curated common uses, require headword or a dictionary-
attested inflection as complete tokens, select different senses before additional
examples of one sense, retain the four-example/two-per-POS caps. No generated
synonym substitution. The original WordNet data remains available for audit.

The offline seed exporter mirrors this policy. Historical seed batches contain
synonym-only examples and remain historical records; regenerate exports from the
current database rather than assuming the old 9,288-row display manifest applies.

## Top-5000 completion (2026-09-20)

The initial 40-word batch above is retained. `top5000-jobs.v1.json` freezes the
original shortfall: 1,493 zero-example words and 771 one-example words. The
frequency list uses the seed exporter's ECDICT ranking, including proper names,
abbreviations and the bound suffix `n't`; it is not a newly curated vocabulary list.

`top5000.v1.jsonl` holds 378 reviewed batches: 2,264 words / 3,757 added examples,
Chinese translations and contextual glosses. DeepSeek Flash generated and separately
reviewed each batch. Failed validation was not accepted; final assistant corrections
are explicitly recorded in `editorialCorrections`. These are LLM-reviewed, not
human-certified. Recorded usage is per retained output and **not** total billing
(includes neither every discarded attempt nor all editorial attempts).

The corpus suffix `n't` must occur in a normal contraction (`can't`, `don't`), never
as an isolated word. Both App and offline validators implement this narrow exception.
All other supplemental targets use complete headword tokens. Original examples may
also use dictionary-attested inflections.

New batch identities reserve ranks -199/-198; the original 40-word batch keeps
-99/-98. Source remains `lingotrip-learner-examples/v1`. New batch requests use empty
candidate-gloss arrays and their precise English sense definitions, keeping cache
identity independent of future flat-dictionary Chinese gloss changes. Apply never
removes WordNet rows. Building the dictionary reapplies both sources.

Current App display total: **11,545 examples for 5,000 words**. Distribution:
4,014 words with two, 427 with three, 559 with four. This minimum refers to displayed
examples after relevance filtering and the App's per-POS/overall caps.

### Repeatable checks and deployment

```
python3 Tools/Dictionary/LearnerExamples/apply.py App/Resources/learner_dictionary.sqlite
python3 Tools/Dictionary/LearnerExamples/verify.py
# Explicit live, read-only verification; never requests paid generation:
python3 Tools/Dictionary/LearnerExamples/verify.py --live-base https://rplearn.haruyuki.cn
```

`batch.py OUTPUT` exports the *current* shortfall (now empty). To resume this original
batch, use the frozen jobs file. `generate_batch.py JOBS OUTPUT_DIRECTORY` runs with
server-owned DEEPSEEK_API_KEY/DEEPSEEK_BASE_URL environment variables, bounded retries,
separate review, saved candidates and atomic completed files. Completed fingerprints
must match the original jobs, so already accepted batches are reused.

`publish_batch.py ROOT` runs on the operator host with `jobs.json` and `results/`.
It uses the existing authenticated internal import API and stores checkpoints only
after every item is ready. The default API is localhost; secrets are never included
in data files. Corrections require invalidating the affected import checkpoint and
reimporting. Versioned old rows remain historical; the catalog selects the latest
completed record for each stable sense ID.

The production catalog reads reviewed rows from authoritative PostgreSQL, with an
indexed lemma query. Clients with fewer than two local examples fetch the catalog,
merge valid examples and display their included translations. Empty results are not
cached, so a subsequent opening sees newly imported content. Offline users keep the
bundled examples. Older clients need **one app update** to gain this reader; later
server supplements need no app update. This release does **not** implement paid
on-demand generation of arbitrary long-tail English examples.
