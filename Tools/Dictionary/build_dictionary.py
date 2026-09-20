#!/usr/bin/env python3
"""构建咕游记随包的全量本地学习词典（仅使用 Python 标准库）。

数据源：
  - ECDICT CSV：英汉释义、音标、词频、考试标签与词形变化；
  - Princeton WordNet 3.1 dict：按词性组织的英文义项、同义词与例句。

默认保留 ECDICT 中所有带中英文释义的词条，不再按考试标签或四万词频裁剪。
如需为调试生成小库，可显式传入 ``--mode core``。

用法：
  python3 Tools/Dictionary/build_dictionary.py ecdict.csv learner_dictionary.sqlite \
      --wordnet-dir /path/to/wordnet/dict
"""

import argparse
import csv
import json
import os
import re
import sqlite3
import sys
from LearnerExamples.apply import apply as apply_learner_examples


CORE_MAX_RANK = 40_000
DEFAULT_SIZE_BUDGET_MB = 99
FORM_CODES = set("pdi3rts")
WORDNET_FILES = {
    "noun": "n",
    "verb": "v",
    "adj": "a",
    "adv": "r",
}
ADJECTIVE_MARKER = re.compile(r"\((?:a|p|ip)\)$")
QUOTED_EXAMPLE = re.compile(r'"([^"]+)"')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv_path", help="ECDICT ecdict.csv 路径")
    parser.add_argument("out_path", help="输出 SQLite 路径")
    parser.add_argument(
        "--wordnet-dir",
        help="WordNet dict 目录；提供后写入结构化英文义项和例句",
    )
    parser.add_argument(
        "--mode",
        choices=("full", "core"),
        default="full",
        help="full 保留全部有效词条；core 使用旧版精简规则",
    )
    parser.add_argument(
        "--size-budget-mb",
        type=float,
        default=DEFAULT_SIZE_BUDGET_MB,
        help="生成文件体积上限，默认 99MB（兼顾 GitHub 单文件限制）",
    )
    return parser.parse_args()


def to_int(value: str | None) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def has_text(value: str | None) -> bool:
    return bool((value or "").strip())


def keep(row: dict[str, str], mode: str) -> bool:
    """全量模式仅排除没有词头或中英文释义都为空的无效行。"""
    if not has_text(row.get("word")):
        return False
    if mode == "full":
        return has_text(row.get("translation")) or has_text(row.get("definition"))
    if to_int(row.get("oxford")) == 1 or to_int(row.get("collins")) >= 1:
        return True
    if has_text(row.get("tag")):
        return True
    return any(
        1 <= to_int(row.get(field)) <= CORE_MAX_RANK
        for field in ("frq", "bnc")
    )


def score(row: dict[str, str]) -> int:
    """忽略大小写后的词头冲突中，保留学习信息更完整的一条。"""
    value = 0
    if has_text(row.get("translation")):
        value += 8
    if has_text(row.get("definition")):
        value += 4
    if to_int(row.get("oxford")) == 1:
        value += 2
    value += min(to_int(row.get("collins")), 5)
    if has_text(row.get("tag")):
        value += 1
    if has_text(row.get("phonetic")):
        value += 1
    return value


def parse_exchange(word: str, exchange: str, lemma_pairs: set[tuple[str, str]]) -> None:
    """展开 ECDICT 词形变化；全量库也保留 form→lemma，供 UI 展示原形。"""
    if not exchange:
        return
    for part in exchange.split("/"):
        if ":" not in part:
            continue
        code, _, form = part.partition(":")
        form = form.strip().lower()
        if not form or form == word:
            continue
        if code in FORM_CODES:
            lemma_pairs.add((form, word))
        elif code == "0":
            lemma_pairs.add((word, form))


def normalized_wordnet_word(value: str) -> str:
    value = ADJECTIVE_MARKER.sub("", value)
    return value.replace("_", " ").lower()


def load_wordnet_synsets(
    wordnet_dir: str,
) -> dict[str, dict[str, tuple[list[str], str, list[str]]]]:
    """读取 data.*，返回 pos→offset→(同义词, 英文定义, 例句)。"""
    result: dict[str, dict[str, tuple[list[str], str, list[str]]]] = {}
    for filename, index_pos in WORDNET_FILES.items():
        path = os.path.join(wordnet_dir, f"data.{filename}")
        synsets: dict[str, tuple[list[str], str, list[str]]] = {}
        with open(path, encoding="utf-8") as source:
            for line in source:
                if not line or line.startswith(" ") or "|" not in line:
                    continue
                fields_text, _, gloss = line.partition("|")
                fields = fields_text.split()
                if len(fields) < 5:
                    continue
                offset = fields[0]
                word_count = int(fields[3], 16)
                words = [
                    normalized_wordnet_word(fields[4 + index * 2])
                    for index in range(word_count)
                ]
                gloss = gloss.strip()
                examples = QUOTED_EXAMPLE.findall(gloss)
                first_example = QUOTED_EXAMPLE.search(gloss)
                definition = (
                    gloss[: first_example.start()] if first_example else gloss
                ).rstrip(" ;")
                if definition:
                    synsets[offset] = (words, definition, examples)
        result[index_pos] = synsets
    return result


def wordnet_sense_rows(
    wordnet_dir: str,
    included_words: set[str],
):
    """按 WordNet index.* 的常用度顺序产出结构化义项。"""
    synsets_by_pos = load_wordnet_synsets(wordnet_dir)
    for filename, pos in WORDNET_FILES.items():
        index_path = os.path.join(wordnet_dir, f"index.{filename}")
        with open(index_path, encoding="utf-8") as source:
            for line in source:
                if not line or line.startswith(" "):
                    continue
                fields = line.split()
                if len(fields) < 7:
                    continue
                word = normalized_wordnet_word(fields[0])
                if word not in included_words:
                    continue
                synset_count = int(fields[2])
                pointer_count = int(fields[3])
                offsets_start = 6 + pointer_count
                offsets = fields[offsets_start : offsets_start + synset_count]
                for rank, offset in enumerate(offsets, start=1):
                    synset = synsets_by_pos[pos].get(offset)
                    if synset is None:
                        continue
                    words, definition, examples = synset
                    synonyms = [item for item in words if item != word]
                    yield (
                        word,
                        rank,
                        pos,
                        definition,
                        json.dumps(examples, ensure_ascii=False) if examples else None,
                        json.dumps(synonyms, ensure_ascii=False) if synonyms else None,
                    )


def build_database(args: argparse.Namespace) -> tuple[int, int, int, int]:
    best: dict[str, dict[str, str]] = {}
    total = 0
    with open(args.csv_path, newline="", encoding="utf-8") as source:
        for row in csv.DictReader(source):
            total += 1
            if not keep(row, args.mode):
                continue
            word = (row.get("word") or "").strip()
            key = word.lower()
            if key not in best or score(row) > score(best[key]):
                best[key] = row

    lemma_pairs: set[tuple[str, str]] = set()
    for key, row in best.items():
        parse_exchange(key, (row.get("exchange") or "").strip(), lemma_pairs)
    lemma_pairs = {
        (form, lemma)
        for form, lemma in lemma_pairs
        if lemma in best and form != lemma
    }

    if os.path.exists(args.out_path):
        os.remove(args.out_path)
    output_dir = os.path.dirname(args.out_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    database = sqlite3.connect(args.out_path)
    database.executescript(
        """
        PRAGMA journal_mode = OFF;
        PRAGMA synchronous = OFF;
        PRAGMA temp_store = MEMORY;
        PRAGMA page_size = 8192;
        CREATE TABLE metadata (
            key TEXT NOT NULL PRIMARY KEY,
            value TEXT NOT NULL
        ) WITHOUT ROWID;
        CREATE TABLE word (
            wl TEXT NOT NULL PRIMARY KEY,
            word TEXT,
            phonetic TEXT,
            definition TEXT,
            translation TEXT,
            pos TEXT,
            collins INTEGER NOT NULL DEFAULT 0,
            oxford INTEGER NOT NULL DEFAULT 0,
            tag TEXT,
            bnc INTEGER NOT NULL DEFAULT 0,
            frq INTEGER NOT NULL DEFAULT 0,
            exchange TEXT
        ) WITHOUT ROWID;
        CREATE TABLE lemma (
            form TEXT NOT NULL,
            lemma TEXT NOT NULL,
            PRIMARY KEY (form, lemma)
        ) WITHOUT ROWID;
        CREATE TABLE sense (
            wl TEXT NOT NULL,
            rank INTEGER NOT NULL,
            pos TEXT NOT NULL,
            definition TEXT NOT NULL,
            examples TEXT,
            synonyms TEXT,
            PRIMARY KEY (wl, pos, rank)
        ) WITHOUT ROWID;
        """
    )
    database.executemany(
        "INSERT INTO word VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        (
            (
                key,
                None if row["word"].strip() == key else row["word"].strip(),
                row.get("phonetic") or None,
                row.get("definition") or None,
                row.get("translation") or None,
                row.get("pos") or None,
                to_int(row.get("collins")),
                to_int(row.get("oxford")),
                (row.get("tag") or "").strip() or None,
                to_int(row.get("bnc")),
                to_int(row.get("frq")),
                (row.get("exchange") or "").strip() or None,
            )
            for key, row in best.items()
        ),
    )
    database.executemany(
        "INSERT OR IGNORE INTO lemma VALUES (?,?)",
        sorted(lemma_pairs),
    )

    # ECDICT incorrectly treats the adjective toasty as a noun with plural toasties.
    database.execute("UPDATE word SET translation = 'n. 烤三明治（toastie 的复数形式）', definition = 'plural of toastie: toasted sandwiches', pos = 'n', exchange = '0:toastie/1:s' WHERE wl = 'toasties'")
    database.execute("UPDATE word SET exchange = NULL WHERE wl = 'toasty'")
    database.execute("UPDATE word SET exchange = 's:toasties' WHERE wl = 'toastie'")
    database.execute("DELETE FROM lemma WHERE form = 'toasties'")
    database.execute("INSERT OR IGNORE INTO lemma SELECT 'toasties', 'toastie' WHERE EXISTS (SELECT 1 FROM word WHERE wl = 'toastie')")

    sense_count = 0
    if args.wordnet_dir:
        for row in wordnet_sense_rows(args.wordnet_dir, set(best)):
            database.execute(
                "INSERT OR IGNORE INTO sense VALUES (?,?,?,?,?,?)",
                row,
            )
            sense_count += 1
        # WordNet 已提供结构化义项时，不再重复保存 ECDICT 的平铺英文定义。
        # 中文释义与全部词条仍完整保留，这一去重可显著降低随包资源体积。
        database.execute(
            """
            UPDATE word
            SET definition = NULL
            WHERE EXISTS (SELECT 1 FROM sense WHERE sense.wl = word.wl)
            """
        )

    apply_learner_examples(database)

    database.executemany(
        "INSERT INTO metadata VALUES (?,?)",
        [
            ("schema_version", "3"),
            ("mode", args.mode),
            ("ecdict_entries", str(len(best))),
            ("lemma_pairs", str(len(lemma_pairs))),
            ("wordnet_senses", str(sense_count)),
            ("sources", "ECDICT; Princeton WordNet 3.1"),
        ],
    )
    database.commit()
    database.execute("VACUUM")
    database.close()
    return total, len(best), len(lemma_pairs), sense_count


def main() -> int:
    args = parse_args()
    total, entries, lemmas, senses = build_database(args)
    size_mb = os.path.getsize(args.out_path) / 1024 / 1024
    print(f"ECDICT 原始词条: {total:,}")
    print(f"本地词条: {entries:,}（模式: {args.mode}）")
    print(f"词形还原对: {lemmas:,}")
    print(f"WordNet 结构化义项: {senses:,}")
    print(f"体积: {size_mb:.1f} MB（预算 {args.size_budget_mb:g} MB）")
    if size_mb > args.size_budget_mb:
        print("!! 超出体积预算；请调整数据列或拆分资源，不要静默裁词。")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
