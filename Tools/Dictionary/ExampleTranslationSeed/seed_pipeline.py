#!/usr/bin/env python3
"""Deterministic queue/export/validation tools for dictionary example translations.

This program never translates text.  Translation is deliberately a reviewed LLM
step: the generated jobs contain the complete source context and the only
accepted completed records are audited JSONL records.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import sys
from typing import Iterable, Iterator


ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DATABASE = ROOT / "App/Resources/learner_dictionary.sqlite"
DICTIONARY_SOURCE = "ecdict-wordnet"
DICTIONARY_VERSION = "v1"
CACHE_KEY_VERSION = "dict-example:v1"
TRANSLATION_MODEL = "gpt-5.6-luna"
TRANSLATION_MODEL_VERSION = "gpt-5.6-luna@2026-09-03"
PROMPT_VERSION = "dictionary-example-zh-hans-v1"
ZH_HANS_RE = re.compile(r"[\u3400-\u9fff]")
SPACE_RE = re.compile(r"\s+")
PLACEHOLDER_TRANSLATION_PREFIXES = (
    "语境示例：",
    "语境示例:",
    "中文翻译：",
    "中文翻译:",
)
PLACEHOLDER_MEANINGS = {
    "语境中的相关义项",
    "相关义项",
    "待定",
    "未确定",
}


POS_PREFIXES = (
    ("interj.", "other"),
    ("pron.", "other"),
    ("prep.", "other"),
    ("conj.", "other"),
    ("adj.", "a"),
    ("adv.", "r"),
    ("aux.", "v"),
    ("vt.", "v"),
    ("vi.", "v"),
    ("num.", "other"),
    ("art.", "other"),
    ("ad.", "r"),
    ("n.", "n"),
    ("v.", "v"),
    ("a.", "a"),
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--database",
        type=Path,
        default=DEFAULT_DATABASE,
        help="learner_dictionary.sqlite (opened read-only)",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("stats", help="print authoritative top-5000 job counts")
    subparsers.add_parser("self-test", help="run parser and pinned-source regressions")

    export = subparsers.add_parser("export", help="atomically export untranslated jobs")
    export.add_argument("--output", type=Path, required=True)
    export.add_argument("--offset", type=int, default=0)
    export.add_argument("--limit", type=int, default=100)
    export.add_argument(
        "--lemma",
        action="append",
        default=[],
        help="only export one lemma; may be repeated (debug/review batches)",
    )
    export.add_argument(
        "--completed",
        type=Path,
        action="append",
        default=[],
        help="completed JSONL batch; may be repeated and is excluded from output",
    )

    validate = subparsers.add_parser("validate", help="validate completed JSONL batches")
    validate.add_argument("batches", type=Path, nargs="+")

    audit = subparsers.add_parser("audit", help="recompute completion and remaining totals")
    audit.add_argument("batches", type=Path, nargs="+")

    merge = subparsers.add_parser(
        "merge",
        help="validate and atomically merge reviewed JSONL parts",
    )
    merge.add_argument("--output", type=Path, required=True)
    merge.add_argument("batches", type=Path, nargs="+")

    render = subparsers.add_parser(
        "render-import",
        help="render a <=100-record slice as the trusted server import payload",
    )
    render.add_argument("--output", type=Path, required=True)
    render.add_argument("--offset", type=int, default=0)
    render.add_argument("--limit", type=int, default=100)
    render.add_argument("batches", type=Path, nargs="+")

    return parser.parse_args()


def open_read_only(path: Path) -> sqlite3.Connection:
    if not path.is_file():
        raise ValueError(f"dictionary not found: {path}")
    database = sqlite3.connect(f"file:{path.resolve()}?mode=ro", uri=True)
    database.row_factory = sqlite3.Row
    return database


def normalize_source_text(value: str) -> str:
    return SPACE_RE.sub(" ", value.strip()).lower()


def source_fingerprint(
    lemma: str,
    part_of_speech: str,
    sense_rank: int,
    sense_definition: str,
    example_index: int,
    example: str,
) -> str:
    canonical = "\n".join(
        (
            DICTIONARY_VERSION,
            lemma.strip().lower(),
            part_of_speech.strip().lower(),
            str(sense_rank),
            normalize_source_text(sense_definition),
            str(example_index),
            normalize_source_text(example),
        )
    )
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def stable_sense_id(
    lemma: str,
    part_of_speech: str,
    sense_rank: int,
    sense_definition: str,
) -> str:
    # Must exactly match DictSense.id in the iOS client.  The unused lemma
    # parameter makes the identity inputs explicit at the call site.
    del lemma
    return f"{part_of_speech}-{sense_rank}-{sense_definition}"


def split_top_level_meanings(value: str) -> list[str]:
    """Split only top-level commas, preserving commas inside paired brackets."""
    opening = set("(（[［{｛【『〈《")
    closing = set(")）]］}｝】』〉》")
    depth = 0
    start = 0
    results: list[str] = []
    for index, character in enumerate(value):
        if character in opening:
            depth += 1
        elif character in closing:
            depth = max(0, depth - 1)
        if character in {",", "，", ";", "；"} and depth == 0:
            item = value[start:index].strip()
            if item:
                results.append(item)
            start = index + 1
    item = value[start:].strip()
    if item:
        results.append(item)
    return results


def candidates_by_pos(translation: str | None) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {"n": [], "v": [], "a": [], "r": [], "other": []}
    if not translation:
        return result
    expanded = translation.replace("\\n", "\n")
    for raw_line in expanded.splitlines():
        line = raw_line.strip()
        lowered = line.lower()
        matched = False
        for prefix, pos in POS_PREFIXES:
            if not lowered.startswith(prefix):
                continue
            meanings = split_top_level_meanings(line[len(prefix) :].strip())
            for meaning in meanings:
                if meaning not in result[pos]:
                    result[pos].append(meaning)
            matched = True
            break
        if not matched:
            for meaning in split_top_level_meanings(line):
                if meaning not in result["other"]:
                    result["other"].append(meaning)
    return result


def iter_top_words(database: sqlite3.Connection) -> Iterator[sqlite3.Row]:
    yield from database.execute(
        """
        WITH ranked AS (
            SELECT
                wl,
                translation,
                exchange,
                bnc,
                frq,
                CASE
                    WHEN bnc = 0 THEN frq
                    WHEN frq = 0 THEN bnc
                    ELSE min(bnc, frq)
                END AS effective_rank,
                ROW_NUMBER() OVER (
                    ORDER BY
                        CASE
                            WHEN bnc = 0 THEN frq
                            WHEN frq = 0 THEN bnc
                            ELSE min(bnc, frq)
                        END,
                        CASE WHEN frq = 0 THEN 2147483647 ELSE frq END,
                        CASE WHEN bnc = 0 THEN 2147483647 ELSE bnc END,
                        wl
                ) AS seed_rank
            FROM word
            WHERE (bnc > 0 OR frq > 0)
              AND instr(wl, ' ') = 0
              AND wl NOT GLOB '*[^A-Za-z''-]*'
        )
        SELECT * FROM ranked WHERE seed_rank <= 5000 ORDER BY seed_rank
        """
    )


def contains_target(sentence: str, word: str, exchange: str | None) -> bool:
    def tokens(text):
        return [token.strip("'") for token in re.findall(r"[a-z]+(?:'[a-z]+)*", text.lower().replace("’", "'"))]
    forms = [word] + [part.split(':', 1)[1] for part in (exchange or '').split('/') if ':' in part and part.split(':', 1)[0] in {'0','p','d','i','3','s','r','t'}]
    actual = tokens(sentence)
    if word.lower() == "n't":
        return any(len(token) > 3 and token.endswith("n't") for token in actual)
    return any(target and any(actual[i:i+len(target)] == target for i in range(len(actual)-len(target)+1)) for target in map(tokens, forms))


def iter_jobs(database: sqlite3.Connection, words=None) -> Iterator[dict[str, object]]:
    abbreviation = {"n": "n.", "v": "v.", "a": "adj.", "s": "adj.", "r": "adv."}

    for word in (iter_top_words(database) if words is None else words):
        meanings = candidates_by_pos(word["translation"])
        sense_rows = database.execute(
            """
            SELECT rank, pos, definition, examples
            FROM sense
            WHERE wl = ?
            ORDER BY rank, pos
            LIMIT 12
            """,
            (word["wl"],),
        ).fetchall()

        ordered_parts_of_speech: list[str] = []
        senses_by_part_of_speech: dict[str, list[sqlite3.Row]] = {}
        for sense in sense_rows:
            pos = sense["pos"]
            if pos not in senses_by_part_of_speech:
                ordered_parts_of_speech.append(pos)
                senses_by_part_of_speech[pos] = []
            senses_by_part_of_speech[pos].append(sense)

        selected: list[tuple[sqlite3.Row, int, str]] = []
        seen: set[str] = set()
        counts_by_display_pos: dict[str, int] = {}

        def append(sense: sqlite3.Row, example_index: int, example: str) -> None:
            display_pos = abbreviation.get(sense["pos"], sense["pos"])
            if len(selected) >= 4 or counts_by_display_pos.get(display_pos, 0) >= 2:
                return
            normalized = SPACE_RE.sub(" ", example.strip())
            identity = normalized.lower()
            if not normalized or identity in seen or not contains_target(normalized, word["wl"], word["exchange"]):
                return
            seen.add(identity)
            counts_by_display_pos[display_pos] = counts_by_display_pos.get(display_pos, 0) + 1
            selected.append((sense, example_index, normalized))

        for pos in ordered_parts_of_speech:
            for sense in senses_by_part_of_speech[pos]:
                if sense["rank"] < 0:
                    for i, text in enumerate(json.loads(sense["examples"] or "[]")):
                        append(sense, i, text)
        # Mirror the App: valid first example per POS, then distinct senses,
        # then remaining examples. Never export a synonym-only sentence.
        for pos in ordered_parts_of_speech:
            if counts_by_display_pos.get(abbreviation.get(pos, pos), 0) > 0:
                continue
            for sense in senses_by_part_of_speech[pos]:
                valid = [(i, text) for i, text in enumerate(json.loads(sense["examples"] or "[]")) if contains_target(text, word["wl"], word["exchange"])]
                if valid:
                    append(sense, *valid[0])
                    break
        for pos in ordered_parts_of_speech:
            for sense in senses_by_part_of_speech[pos]:
                valid = [(i, text) for i, text in enumerate(json.loads(sense["examples"] or "[]")) if contains_target(text, word["wl"], word["exchange"])]
                if valid:
                    append(sense, *valid[0])
        for pos in ordered_parts_of_speech:
            for sense in senses_by_part_of_speech[pos]:
                for i, text in enumerate(json.loads(sense["examples"] or "[]")):
                    append(sense, i, text)

        for sense, example_index, example in selected:
            fingerprint = source_fingerprint(
                word["wl"],
                sense["pos"],
                sense["rank"],
                sense["definition"],
                example_index,
                example,
            )
            candidate_pos = "a" if sense["pos"] == "s" else sense["pos"]
            yield {
                "schemaVersion": 1,
                "cacheKey": f"{CACHE_KEY_VERSION}:{fingerprint}",
                "sourceFingerprint": fingerprint,
                "stableSenseId": stable_sense_id(
                    word["wl"],
                    sense["pos"],
                    sense["rank"],
                    sense["definition"],
                ),
                "dictionarySource": "lingotrip-learner-examples" if sense["rank"] < 0 else DICTIONARY_SOURCE,
                "dictionaryVersion": DICTIONARY_VERSION,
                "seedRank": word["seed_rank"],
                "frequencyRank": word["effective_rank"],
                "lemma": word["wl"],
                "partOfSpeech": sense["pos"],
                "senseRank": sense["rank"],
                "senseDefinition": sense["definition"],
                "exampleIndex": example_index,
                "sentence": example,
                "candidateMeaningsZhHans": [] if sense["rank"] < -100 else meanings.get(candidate_pos, []),
            }


def load_records(paths: Iterable[Path]) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    for path in paths:
        with path.open(encoding="utf-8") as source:
            for line_number, line in enumerate(source, start=1):
                if not line.strip():
                    continue
                try:
                    record = json.loads(line)
                except json.JSONDecodeError as error:
                    raise ValueError(f"{path}:{line_number}: invalid JSON: {error}") from error
                record["__location"] = f"{path}:{line_number}"
                records.append(record)
    return records


def completed_keys(paths: Iterable[Path]) -> set[str]:
    return {str(record.get("cacheKey", "")) for record in load_records(paths)}


def atomic_write_jsonl(path: Path, records: Iterable[dict[str, object]]) -> int:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    count = 0
    try:
        with temporary.open("x", encoding="utf-8", newline="\n") as output:
            for record in records:
                output.write(json.dumps(record, ensure_ascii=False, sort_keys=True))
                output.write("\n")
                count += 1
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()
    return count


def atomic_write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.tmp-{os.getpid()}")
    try:
        with temporary.open("x", encoding="utf-8", newline="\n") as output:
            json.dump(value, output, ensure_ascii=False, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, path)
    finally:
        if temporary.exists():
            temporary.unlink()


def validate_records(
    records: list[dict[str, object]],
    expected_by_key: dict[str, dict[str, object]],
) -> list[str]:
    errors: list[str] = []
    seen: set[str] = set()
    source_fields = (
        "schemaVersion",
        "cacheKey",
        "sourceFingerprint",
        "stableSenseId",
        "dictionarySource",
        "dictionaryVersion",
        "seedRank",
        "frequencyRank",
        "lemma",
        "partOfSpeech",
        "senseRank",
        "senseDefinition",
        "exampleIndex",
        "sentence",
        "candidateMeaningsZhHans",
    )
    completed_fields = (
        "sentenceZhHans",
        "contextualMeaningZhHans",
        "meaningSelection",
        "selectionNote",
        "model",
        "promptVersion",
        "reviewStatus",
    )
    required_fields = set(source_fields + completed_fields)
    allowed_fields = required_fields | {"selectedMeaningIndex"}
    for record in records:
        location = str(record.get("__location", "unknown"))
        actual_fields = set(record) - {"__location"}
        missing_fields = required_fields - actual_fields
        extra_fields = actual_fields - allowed_fields
        if missing_fields:
            errors.append(f"{location}: missing fields: {', '.join(sorted(missing_fields))}")
        if extra_fields:
            errors.append(f"{location}: unknown fields: {', '.join(sorted(extra_fields))}")
        key = str(record.get("cacheKey", ""))
        if not key:
            errors.append(f"{location}: missing cacheKey")
            continue
        if key in seen:
            errors.append(f"{location}: duplicate cacheKey {key}")
        seen.add(key)
        expected = expected_by_key.get(key)
        if expected is None:
            errors.append(f"{location}: cacheKey is not in the current top-5000 source queue")
            continue
        for field in source_fields:
            if record.get(field) != expected.get(field):
                errors.append(f"{location}: source field {field} does not match dictionary")

        translation = record.get("sentenceZhHans")
        meaning = record.get("contextualMeaningZhHans")
        selection = record.get("meaningSelection")
        note = record.get("selectionNote")
        if not isinstance(translation, str) or not translation.strip():
            errors.append(f"{location}: sentenceZhHans must be non-empty")
        elif not ZH_HANS_RE.search(translation):
            errors.append(f"{location}: sentenceZhHans contains no Han character")
        elif len(translation) > 2000:
            errors.append(f"{location}: sentenceZhHans is over 2000 characters")
        elif translation.strip().startswith(PLACEHOLDER_TRANSLATION_PREFIXES):
            errors.append(f"{location}: sentenceZhHans is a labelled placeholder")
        else:
            source_sentence = normalize_source_text(str(expected["sentence"]))
            normalized_translation = normalize_source_text(translation)
            if len(source_sentence) >= 8 and source_sentence in normalized_translation:
                errors.append(f"{location}: sentenceZhHans echoes the complete English source")
        if not isinstance(meaning, str) or not meaning.strip():
            errors.append(f"{location}: contextualMeaningZhHans must be non-empty")
        elif not ZH_HANS_RE.search(meaning):
            errors.append(f"{location}: contextualMeaningZhHans contains no Han character")
        elif len(meaning) > 40:
            errors.append(f"{location}: contextual meaning is not minimal (over 40 characters)")
        elif meaning.strip() in PLACEHOLDER_MEANINGS or meaning.strip().startswith("efine"):
            errors.append(f"{location}: contextualMeaningZhHans is a placeholder")

        candidates = expected["candidateMeaningsZhHans"]
        selected_index = record.get("selectedMeaningIndex")
        if selection == "candidate":
            if meaning not in candidates:
                errors.append(f"{location}: candidate selection is not one exact candidate")
            expected_index = candidates.index(meaning) if meaning in candidates else None
            if (
                not isinstance(selected_index, int)
                or isinstance(selected_index, bool)
                or selected_index != expected_index
            ):
                errors.append(
                    f"{location}: selectedMeaningIndex does not identify the meaning"
                )
        elif selection == "refined":
            if not isinstance(note, str) or not note.strip():
                errors.append(f"{location}: refined meaning requires selectionNote")
            if "selectedMeaningIndex" in record:
                errors.append(
                    f"{location}: refined meaning must not claim a candidate index"
                )
        else:
            errors.append(f"{location}: meaningSelection must be candidate or refined")
        if not isinstance(note, str) or not note.strip():
            errors.append(f"{location}: selectionNote must be non-empty")
        elif len(note) > 300:
            errors.append(f"{location}: selectionNote is over 300 characters")

        if len(candidates) > 1 and isinstance(meaning, str):
            collapsed_meaning = re.sub(r"[\s,，]", "", meaning)
            collapsed_all = re.sub(r"[\s,，]", "", ",".join(candidates))
            if collapsed_meaning == collapsed_all:
                errors.append(f"{location}: contextual meaning repeats the whole POS meaning group")

        if record.get("model") != TRANSLATION_MODEL:
            errors.append(f"{location}: model must be {TRANSLATION_MODEL}")
        if record.get("promptVersion") != PROMPT_VERSION:
            errors.append(f"{location}: unexpected promptVersion")
        if record.get("reviewStatus") != "llm-reviewed":
            errors.append(f"{location}: reviewStatus must be llm-reviewed")
    return errors


def validate_cross_batch_alignment(
    records: list[dict[str, object]],
) -> list[str]:
    """Detect accidental same-row reuse of another large batch's translations.

    Legitimate short examples can share a Chinese rendering, so isolated matches are
    allowed. A large number of same-index matches between two independent source
    batches is the characteristic failure mode of an incorrectly reused translation
    array and must block import.
    """
    by_path: dict[str, list[dict[str, object]]] = {}
    for record in records:
        location = str(record.get("__location", "unknown"))
        path, _, _ = location.rpartition(":")
        by_path.setdefault(path, []).append(record)

    errors: list[str] = []
    paths = sorted(by_path)
    for left_index, left_path in enumerate(paths):
        left = by_path[left_path]
        if len(left) < 100:
            continue
        for right_path in paths[left_index + 1 :]:
            right = by_path[right_path]
            if len(right) < 100:
                continue
            suspicious_rows = [
                index + 1
                for index, (left_record, right_record) in enumerate(zip(left, right))
                if left_record.get("sentence") != right_record.get("sentence")
                and left_record.get("sentenceZhHans")
                == right_record.get("sentenceZhHans")
            ]
            if len(suspicious_rows) >= 10:
                preview = ", ".join(str(row) for row in suspicious_rows[:8])
                errors.append(
                    f"{left_path} and {right_path}: {len(suspicious_rows)} same-row "
                    f"translations reuse different English sources (rows {preview})"
                )
    return errors


def main() -> int:
    args = parse_args()
    database = open_read_only(args.database)
    try:
        jobs = list(iter_jobs(database))
    finally:
        database.close()

    if args.command == "stats":
        word_count = len({int(job["seedRank"]) for job in jobs})
        represented_lemmas = len({str(job["lemma"]) for job in jobs})
        sense_count = len(
            {
                (str(job["lemma"]), str(job["partOfSpeech"]), int(job["senseRank"]))
                for job in jobs
            }
        )
        print(
            json.dumps(
                {
                    "dictionarySource": "mixed: ecdict-wordnet; lingotrip-learner-examples",
                    "dictionaryVersion": DICTIONARY_VERSION,
                    "topWordTarget": 5000,
                    "topWordsWithExamples": represented_lemmas,
                    "topWordRanksRepresentedByExamples": word_count,
                    "sensesWithExamples": sense_count,
                    "exampleJobs": len(jobs),
                    "maximumSentenceLength": max(len(str(job["sentence"])) for job in jobs),
                    "maximumStableSenseIdLength": max(
                        len(str(job["stableSenseId"])) for job in jobs
                    ),
                    "maximumCandidateCount": max(
                        len(job["candidateMeaningsZhHans"]) for job in jobs
                    ),
                    "maximumCandidateLength": max(
                        (
                            len(str(candidate))
                            for job in jobs
                            for candidate in job["candidateMeaningsZhHans"]
                        ),
                        default=0,
                    ),
                    "jobsOver24Candidates": sum(
                        len(job["candidateMeaningsZhHans"]) > 24 for job in jobs
                    ),
                    "jobsWithCandidateOver160Characters": sum(
                        any(
                            len(str(candidate)) > 160
                            for candidate in job["candidateMeaningsZhHans"]
                        )
                        for job in jobs
                    ),
                    "stableSenseIdsOver128Characters": sum(
                        len(str(job["stableSenseId"])) > 128 for job in jobs
                    ),
                },
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
        )
        return 0

    if args.command == "self-test":
        nested = split_top_level_meanings("第一义, (专业,旧称)第二义，第三义")
        if nested != ["第一义", "(专业,旧称)第二义", "第三义"]:
            raise ValueError(f"nested-comma parser regression: {nested}")
        mate_jobs = [job for job in jobs if job["lemma"] == "mate"]
        if not mate_jobs or any("teammates" in str(job["sentence"]) or "coupled" in str(job["sentence"]) for job in mate_jobs):
            raise ValueError("mate synonyms/substrings leaked into display jobs")
        if not any(job["lemma"] == "which" and job["dictionarySource"] == "lingotrip-learner-examples" for job in jobs):
            raise ValueError("learner supplement missing")
        if not all(str(job["cacheKey"]).endswith(str(job["sourceFingerprint"])) for job in jobs):
            raise ValueError("cache key/fingerprint mismatch")
        print(
            "self-test passed: nested commas, target-word filtering, "
            "App display selection, mate regression, cache keys"
        )
        return 0

    if args.command == "export":
        if args.offset < 0 or args.limit < 1:
            raise ValueError("offset must be >= 0 and limit must be >= 1")
        done = completed_keys(args.completed)
        lemma_filter = {lemma.strip().lower() for lemma in args.lemma if lemma.strip()}
        pending = (
            job
            for job in jobs
            if str(job["cacheKey"]) not in done
            and (not lemma_filter or str(job["lemma"]) in lemma_filter)
        )
        selected = []
        for index, job in enumerate(pending):
            if index < args.offset:
                continue
            selected.append(job)
            if len(selected) == args.limit:
                break
        count = atomic_write_jsonl(args.output, selected)
        print(f"exported {count} untranslated jobs to {args.output}")
        return 0

    expected_by_key = {str(job["cacheKey"]): job for job in jobs}
    records = load_records(args.batches)
    errors = validate_records(records, expected_by_key)
    errors.extend(validate_cross_batch_alignment(records))
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        print(f"validation failed: {len(errors)} error(s)", file=sys.stderr)
        return 1

    unique_complete = len({str(record["cacheKey"]) for record in records})
    if args.command == "validate":
        print(f"validated {unique_complete} reviewed translations")
    elif args.command == "audit":
        print(
            json.dumps(
                {
                    "totalExampleJobs": len(jobs),
                    "completedExampleJobs": unique_complete,
                    "remainingExampleJobs": len(jobs) - unique_complete,
                    "completionPercent": round(unique_complete / len(jobs) * 100, 4),
                },
                ensure_ascii=False,
                indent=2,
                sort_keys=True,
            )
        )
    elif args.command == "merge":
        clean_records = [
            {key: value for key, value in record.items() if key != "__location"}
            for record in records
        ]
        count = atomic_write_jsonl(args.output, clean_records)
        print(f"validated and merged {count} reviewed translations to {args.output}")
    else:
        if args.offset < 0 or args.limit < 1 or args.limit > 100:
            raise ValueError("render-import requires offset >= 0 and limit in 1...100")
        items = []
        for record in records[args.offset : args.offset + args.limit]:
            item = {
                "candidateMeaningsZhHans": record["candidateMeaningsZhHans"],
                "contextualMeaningZhHans": record["contextualMeaningZhHans"],
                "dictionary": {
                    "source": record["dictionarySource"],
                    "version": record["dictionaryVersion"],
                },
                "lemma": record["lemma"],
                "partOfSpeech": record["partOfSpeech"],
                "promptVersion": record["promptVersion"],
                "senseDefinitionEn": record["senseDefinition"],
                "sentence": record["sentence"],
                "sentenceZhHans": record["sentenceZhHans"],
                "stableSenseId": record["stableSenseId"],
                "translationModelVersion": TRANSLATION_MODEL_VERSION,
            }
            if record["meaningSelection"] == "candidate":
                item["selectedMeaningIndex"] = record["selectedMeaningIndex"]
            items.append(item)
        atomic_write_json(args.output, {"items": items})
        print(f"rendered {len(items)} trusted-import items to {args.output}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, sqlite3.Error) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
