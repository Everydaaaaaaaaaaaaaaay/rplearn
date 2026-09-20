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
