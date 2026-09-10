#!/usr/bin/env python3
"""Translate the fixed NPC dialogue sample locally with a predownloaded HY-MT model.

Run in a separate environment containing mlx-lm==0.31.3. No model downloads,
cloud inference, story writes, or translation postprocessing happen here.
"""
import argparse
import json
import os
from pathlib import Path
import time

MODEL_ID = "mlx-community/HY-MT1.5-1.8B-4bit"
MODEL_REVISION = "f6911967a04cfbeb2246a164fe1af5da2cc093ad"
NODE_IDS = [
    "hello", "hello_part2", "cancel", "nora_boundary", "private_2_part2",
    "format_4", "not_test", "read_yes_part2", "remember_private", "next_day",
]


def sample(story):
    nodes = {node["id"]: node for node in json.loads(story.read_text())["nodes"]}
    return [dict(id=index, node_id=node_id, speaker=nodes[node_id]["speaker"],
                 english=nodes[node_id]["text"])
            for index, node_id in enumerate(NODE_IDS, 1)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model-path", type=Path, required=True)
    parser.add_argument("--story", type=Path, default=Path("App/Resources/Stories/departures_london_v1.json"))
    parser.add_argument("--output", type=Path, default=Path("build/verification/hymt18-npc-translation/output.json"))
    args = parser.parse_args()
    if not args.model_path.is_dir():
        parser.error("--model-path must be an existing local model directory")
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    import mlx.core as mx
    from mlx_lm import generate, load
    from mlx_lm.sample_utils import make_logits_processors, make_sampler

    rows = sample(args.story)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    started = time.perf_counter()
    print("Loading local model...", flush=True)
    model, tokenizer = load(str(args.model_path))
    load_seconds = time.perf_counter() - started
    print(f"Loaded in {load_seconds:.2f}s", flush=True)
    results = []
    for row in rows:
        # Supply only the original English line, never the story's Chinese reference.
        prompt = (
            "将以下文本翻译为简体中文，注意只需要输出翻译后的结果，不要额外解释：\n"
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
                      mode="local offline, 4-bit, sentence only, no post-editing",
                      source=str(args.story), load_seconds=load_seconds, results=results)
        temporary = args.output.with_suffix(".tmp")
        temporary.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n")
        temporary.replace(args.output)
        print(f"{row['id']:02d} [{result['elapsed_seconds']:.2f}s] {translation}", flush=True)
        mx.clear_cache()


if __name__ == "__main__":
    main()
