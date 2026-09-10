#!/usr/bin/env python3
"""Translate the fixed 20-example sample locally with a predownloaded HY-MT model.

Run in a separate environment containing mlx-lm==0.31.3. No model downloads,
cloud inference, dictionary writes, or translation postprocessing happen here.
"""
import argparse
import json
import os
from pathlib import Path
import re
import sqlite3
import time

MODEL_ID = "mlx-community/HY-MT1.5-7B-4bit"
MODEL_REVISION = "806395bf6a0be05660f5b44519152582c7336715"
WORDS = "book miss fine get take order check run right break leave catch make mind keep turn pay feel meet work".split()


def sample(database):
    rows = []
    with sqlite3.connect(database.resolve().as_uri() + "?mode=ro", uri=True) as connection:
        for word in WORDS:
            senses = connection.execute(
                "select pos,rank,definition,examples from sense where wl=? order by pos,rank", (word,)
            )
            for pos, rank, definition, examples in senses:
                candidates = [
                    sentence for sentence in json.loads(examples or "[]")
                    if 6 <= len(sentence.split()) <= 22
                    and re.search(r"\b" + re.escape(word) + r"\w*\b", sentence, re.I)
                ]
                if candidates:
                    rows.append(dict(id=len(rows) + 1, word=word, pos=pos, rank=rank,
                                     definition=definition, english=candidates[0]))
                    break
    if len(rows) != 20:
        raise RuntimeError(f"Expected 20 fixed examples, got {len(rows)}")
    return rows


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-path", type=Path, required=True)
    parser.add_argument("--database", type=Path, default=Path("App/Resources/learner_dictionary.sqlite"))
    parser.add_argument("--output", type=Path, default=Path("build/verification/hymt-translation-20/output.json"))
    args = parser.parse_args()
    if not args.model_path.is_dir():
        parser.error("--model-path must be an existing local model directory")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    import mlx.core as mx
    from mlx_lm import generate, load
    from mlx_lm.sample_utils import make_logits_processors, make_sampler

    rows = sample(args.database)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    print("Loading local model...", flush=True)
    model, tokenizer = load(str(args.model_path))
    print(f"Loaded in {time.perf_counter() - started:.2f}s", flush=True)
    results = []
    for row in rows:
        # Follow the model card's contextual translation template. The context is
        # dictionary metadata, never a manually supplied target translation.
        prompt = (
            f"这是英汉词典的例句。目标词：{row['word']}；词性：{row['pos']}。\n"
            f"该词在此例句中的英文义项：{row['definition']}\n"
            "参考上面的信息，把下面的文本翻译成简体中文，注意不需要翻译上文，也不要额外解释：\n"
            + row["english"]
        )
        formatted = tokenizer.apply_chat_template(
            [{"role": "user", "content": prompt}], tokenize=False, add_generation_prompt=True
        )
        mx.random.seed(20260911 + row["id"])
        started = time.perf_counter()
        translation = generate(
            model, tokenizer, prompt=formatted, max_tokens=256, verbose=False,
            sampler=make_sampler(temp=0.7, top_p=0.6, top_k=20),
            logits_processors=make_logits_processors(repetition_penalty=1.05),
        )
        result = dict(row, chinese=translation, elapsed_seconds=time.perf_counter() - started,
                      prompt=prompt, seed=20260911 + row["id"])
        results.append(result)
        record = dict(model=MODEL_ID, revision=MODEL_REVISION, runtime="mlx-lm 0.31.3",
                      mode="local offline, 4-bit, dictionary context, no post-editing", results=results)
        temporary = args.output.with_suffix(".tmp")
        temporary.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
        temporary.replace(args.output)
        print(f"{row['id']:02d} [{result['elapsed_seconds']:.2f}s] {translation}", flush=True)
        mx.clear_cache()


if __name__ == "__main__":
    main()
