#!/usr/bin/env python3
"""ECDICT 全量 CSV → ecdict_lite.sqlite 预处理脚本（仅用 Python 标准库）。

过滤策略：保留 oxford==1 或 collins>=1 或 tag 非空（zk/gk/cet4/6/ky/
toefl/ielts/gre 等）或 frq/bnc 在 1..40000 之间的词条。预计 6-9 万主词条。

产出两张表：
  word  — 主词条，按小写唯一（wl 为主键）
  lemma — 词形还原反查表（looked → look），由 exchange 字段双向展开

用法：
  python3 tools/ecdict/build_dict.py <ecdict.csv> <输出 sqlite 路径>
"""

import csv
import os
import sqlite3
import sys

MAX_RANK = 40000
SIZE_BUDGET_MB = 50

# exchange 字段的变形类型码：p 过去式 / d 过去分词 / i 现在分词 / 3 三单 /
# r 比较级 / t 最高级 / s 复数。0 指向原型（lemma），1 是变形方式说明（跳过）。
FORM_CODES = set("pdi3rts")


def to_int(value: str) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def keep(row: dict) -> bool:
    if to_int(row["oxford"]) == 1:
        return True
    if to_int(row["collins"]) >= 1:
        return True
    if (row["tag"] or "").strip():
        return True
    frq = to_int(row["frq"])
    if 1 <= frq <= MAX_RANK:
        return True
    bnc = to_int(row["bnc"])
    if 1 <= bnc <= MAX_RANK:
        return True
    return False


def score(row: dict) -> int:
    """小写形式冲突时（如 Hood/hood）保留信息量更高的词条。"""
    value = 0
    if (row["translation"] or "").strip():
        value += 4
    if to_int(row["oxford"]) == 1:
        value += 2
    value += min(to_int(row["collins"]), 5)
    if (row["tag"] or "").strip():
        value += 1
    if (row["phonetic"] or "").strip():
        value += 1
    return value


def parse_exchange(word: str, exchange: str, lemma_pairs: set):
    """双向展开 exchange：
    - 该词条列出的变形（p:/d:/i:/3:/r:/t:/s:）→ (变形, 本词)
    - 该词条自带的原型指针（0:）→ (本词, 原型)
    """
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


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 1
    csv_path, out_path = sys.argv[1], sys.argv[2]

    best: dict[str, dict] = {}
    total = 0
    with open(csv_path, newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            total += 1
            word = (row["word"] or "").strip()
            if not word or not keep(row):
                continue
            wl = word.lower()
            if wl not in best or score(row) > score(best[wl]):
                best[wl] = row

    lemma_pairs: set = set()
    for wl, row in best.items():
        parse_exchange(wl, (row["exchange"] or "").strip(), lemma_pairs)
    # 只保留原型确实收录在主表里的还原对，且变形本身不是主词条（主词条走精确命中）。
    lemma_pairs = {(form, lemma) for form, lemma in lemma_pairs
                   if lemma in best and form not in best}

    if os.path.exists(out_path):
        os.remove(out_path)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    db = sqlite3.connect(out_path)
    db.executescript(
        """
        PRAGMA journal_mode = OFF;
        CREATE TABLE word (
            wl TEXT NOT NULL PRIMARY KEY,
            word TEXT NOT NULL,
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
        """
    )
    db.executemany(
        "INSERT INTO word VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
        (
            (
                wl,
                row["word"].strip(),
                row["phonetic"] or None,
                row["definition"] or None,
                row["translation"] or None,
                row["pos"] or None,
                to_int(row["collins"]),
                to_int(row["oxford"]),
                (row["tag"] or "").strip() or None,
                to_int(row["bnc"]),
                to_int(row["frq"]),
                (row["exchange"] or "").strip() or None,
            )
            for wl, row in best.items()
        ),
    )
    db.executemany("INSERT OR IGNORE INTO lemma VALUES (?,?)", sorted(lemma_pairs))
    db.commit()
    db.execute("VACUUM")
    db.close()

    size_mb = os.path.getsize(out_path) / 1024 / 1024
    print(f"总词条: {total}, 收录主词条: {len(best)}, 词形还原对: {len(lemma_pairs)}")
    print(f"体积: {size_mb:.1f} MB (预算 {SIZE_BUDGET_MB} MB)")
    if size_mb > SIZE_BUDGET_MB:
        print("!! 超出体积预算：请砍 definition 列或收紧过滤阈值")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
