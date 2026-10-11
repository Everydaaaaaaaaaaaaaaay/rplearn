#!/usr/bin/env python3
"""只读核验已人工审定台词的本地音频；不合成、改写或发布教学内容。"""
import hashlib
import json
from pathlib import Path
import re
import sys
import wave

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUTPUT = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else ROOT / "build/learning-junior-20261011"
CONTRACTIONS = {"i'm": "i am", "it's": "it is", "we're": "we are", "didn't": "did not",
                "we've": "we have", "isn't": "is not", "don't": "do not", "i'll": "i will",
                "i'd": "i would", "where's": "where is", "they're": "they are"}
NUMBERS = {"1": "one", "2": "two", "3": "three", "7": "seven", "12": "twelve"}


def normalized(text):
    # 只处理本批已明确的正字法、缩写与金额书写；不忽略否定、时态或额外词。
    text = re.sub(r"\$(\d+)", r"\1 dollars", text)
    words = re.findall(r"[a-z]+(?:'[a-z]+)?|[0-9]+", text.lower().replace("’", "'"))
    return [token for word in words
            for token in CONTRACTIONS.get(word, NUMBERS.get(word, {"practise": "practice"}.get(word, word))).split()]


def read_pcm(path):
    with wave.open(str(path)) as audio:
        assert (audio.getframerate(), audio.getnchannels(), audio.getsampwidth()) == (24000, 1, 2)
        return np.frombuffer(audio.readframes(audio.getnframes()), dtype="<i2")


reports = []
audit_document = json.loads((ROOT / "Backend/config/learning/authoring/junior-audio-review-2026-10-11.json").read_text())
audit = {row["questionId"]: row for row in audit_document["clips"]}
assert len(audit) == len(audit_document["clips"]) == 34
for level, expected_count in [("junior1", 13), ("junior2", 12), ("junior3", 9)]:
    folder = OUTPUT / level
    load = lambda name: json.loads((folder / name).read_text())
    draft = json.loads((ROOT / f"Backend/config/learning/authoring/{level}.astra.json").read_text())
    scripts = {q["id"]: q["audioScript"] for q in draft["questions"] if q.get("audioScript")}
    selection = load("selection.json")
    manifests = {row["questionId"]: row for row in load("manifest.json")}
    plans = {row["questionId"]: row for row in load("production-plan.json")["clips"]}
    assert load("missing.json") == []
    assert len(selection) == expected_count == len(scripts)
    assert {row["questionId"] for row in selection} == set(scripts) == set(manifests) == set(plans)
    for row in selection:
        key = row["questionId"]
        manifest, plan = manifests[key], plans[key]
        assert row["text"] == manifest["transcript"] == plan["transcript"] == scripts[key], key
        assert audit[key]["audioScript"] == scripts[key]
        assert audit[key]["audioScriptSha256"] == hashlib.sha256(scripts[key].encode()).hexdigest()
        path = Path(row["masterPath"])
        assert path.parent == folder
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        assert digest == row["masterStats"]["sha256"] == manifest["masterSha256"]
        assert digest == audit[key]["sha256"]
        assert audit[key]["masterRecognition"] == row["masterRecognition"]
        pcm = read_pcm(path)
        peak = int(np.abs(pcm.astype(np.int32)).max())
        duration = len(pcm) / 24000
        assert 0 < peak <= 27000 and 0 < duration < 60
        active = np.flatnonzero(np.abs(pcm.astype(np.int32)) > 128)
        assert len(active) and active[0] / 24000 < 0.7 and (len(pcm) - 1 - active[-1]) / 24000 < 0.9
        wpm = len(row["text"].split()) / duration * 60
        assert abs(wpm - row["wpm"]) < 1e-9 and plan["minimumWpm"] <= wpm <= plan["maximumWpm"]
        assert len(manifest["segments"]) == 1 and manifest["gaps"] == []
        segment = manifest["segments"][0]
        assert segment["text"] == scripts[key] and segment["startSample"] == 0
        source = Path(segment["sourcePath"])
        assert source.parent == folder and hashlib.sha256(source.read_bytes()).hexdigest() == segment["sha256"]
        original = read_pcm(source).astype(np.float64)
        assert segment["endSampleExclusive"] == len(original)
        gain = min(3000 / float(np.sqrt(np.mean(original * original))), 27000 / float(np.abs(original).max()))
        assert abs(gain - row["gain"]) < 1e-12
        assert np.array_equal(pcm, np.rint(original * gain).astype("<i2")), "母版必须仅为整段增益，不剪词或变速"
        for model in ["base.en", "small.en"]:
            for evidence in [row["masterRecognition"][model], segment["candidateRecognition"][model]]:
                assert evidence["exact"] and normalized(evidence["text"]) == normalized(scripts[key]), key
        reports.append({"level": level, "questionId": key, "file": str(path.relative_to(ROOT)),
                        "sha256": digest, "durationMs": round(duration * 1000), "wpm": round(wpm, 2),
                        "voice": segment["voice"], "take": segment["take"], "rate": segment["speed"]})

assert set(audit) == {row["questionId"] for row in reports}
for row in reports:
    assert all(audit[row["questionId"]][key] == value for key, value in row.items())
print(json.dumps({"clips": reports, "count": len(reports),
                  "scope": "台词、候选及母版双ASR、逐采样增益、波形与语速通过；未声称独立人耳听感、原生播放或正式发布通过。"}, ensure_ascii=False, indent=2))
