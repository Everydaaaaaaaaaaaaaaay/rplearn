#!/usr/bin/env python3
"""只读核验小四至小六音频，JSON写到标准输出，不修改媒体或审阅目录。"""
import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path
import re
import sys
import wave

ROOT = Path(__file__).resolve().parent.parent
AUTHORING = ROOT / "Backend/config/learning/authoring"
LEVELS = {"primary4": 7, "primary5": 6, "primary6": 6}
MODELS = {"base.en", "small.en"}
VOICES = {"F3", "M3", "M5"}
CONTRACTIONS = {
    "i'm": "i am", "it's": "it is", "we're": "we are", "they're": "they are",
    "you're": "you are", "she's": "she is", "he's": "he is", "that's": "that is",
    "didn't": "did not", "isn't": "is not", "don't": "do not", "doesn't": "does not",
    "wasn't": "was not", "weren't": "were not", "couldn't": "could not",
    "can't": "can not", "cannot": "can not", "won't": "will not",
    "we've": "we have", "i'll": "i will", "i'd": "i would", "where's": "where is",
}
NUMBERS = {"1": "one", "2": "two", "3": "three", "4": "four", "5": "five",
           "6": "six", "7": "seven", "8": "eight", "9": "nine", "10": "ten",
           "12": "twelve", "40": "forty", "1st": "first"}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def normalized(text):
    # 保留所有格、否定、词尾及币种；Mia's绝不改成me as或去掉s。
    value = text.lower().replace("’", "'").replace("‘", "'")
    value = re.sub(r"\$(\d+(?:\.\d+)?)", r"\1 dollars", value)
    value = re.sub(r"[¥￥](\d+(?:\.\d+)?)", r"\1 yuan", value)
    words = re.findall(r"[a-z]+(?:'[a-z]+)?|\d+(?:\.\d+)?(?:st|nd|rd|th)?|[$¥￥£€]", value)
    return [part for word in words
            for part in CONTRACTIONS.get(word, NUMBERS.get(word, {"practise": "practice"}.get(word, word))).split()]


def read_pcm(path):
    with wave.open(str(path), "rb") as audio:
        require((audio.getframerate(), audio.getnchannels(), audio.getsampwidth(), audio.getcomptype())
                == (24000, 1, 2, "NONE"), f"PCM格式不符：{path.name}")
        samples = array("h", audio.readframes(audio.getnframes()))
    if sys.byteorder != "little":
        samples.byteswap()
    require(len(samples) > 0, f"空音频：{path.name}")
    return samples


def index_rows(rows, label):
    require(isinstance(rows, list), f"{label}必须是数组")
    result = {row["questionId"]: row for row in rows}
    require(len(result) == len(rows), f"{label}题号重复")
    return result


def check_asr(records, text, label):
    require(isinstance(records, dict) and set(records) == MODELS, f"{label}缺少双模型识别")
    expected = normalized(text)
    for model in sorted(MODELS):
        evidence = records[model]
        require(evidence.get("exact") is True, f"{label}/{model}未标记exact")
        require(isinstance(evidence.get("text"), str), f"{label}/{model}缺少识别原文")
        require(normalized(evidence["text"]) == expected,
                f"{label}/{model}独立正字法比较不符：{evidence['text']!r}")
    return records


def local_path(value, folder):
    path = Path(value)
    if not path.is_absolute():
        path = folder / path
    path = path.resolve(strict=True)
    require(path.parent == folder, f"媒体路径不在本年级目录：{path}")
    return path


def verify_clip(level, key, script, plan, row, manifest, folder, load_json, load_bytes):
    require(plan["transcript"] == script, "制作计划原文与formal.audioScript不同")
    require(row["transcript"] == manifest["transcript"] == script, "selection/manifest原文不同")
    segments = plan["segments"]
    require(len(segments) in (1, 2), "本批仅允许一个或两个完整话轮")
    spoken = " ".join(segment["text"] for segment in segments)
    # 有标签脚本只能按计划的说话人前缀剥离；没有宽泛删除任意专名的规则。
    labelled = " ".join(f"{segment['speaker']}: {segment['text']}" for segment in segments)
    require(script in (spoken, labelled), "计划话轮没有精确保留作者原文/角色标签")
    require(row["text"] == spoken, "selection朗读正文不等于完整话轮连接")
    require(len(manifest["segments"]) == len(row["segments"]) == len(segments), "完整话轮缺失")
    expected_voice = "+".join(sorted({segment["voice"] for segment in segments}))
    require(all(segment["voice"] in VOICES for segment in segments), "未授权的制作声线")
    require(row["voice"] == expected_voice, "母版声线映射不符")
    require(row["speakers"] == [{"id": segment["speaker"], "voice": segment["voice"]}
                                for segment in segments], "母版说话人映射不符")
    require(row["interSegmentSilenceMs"] == (300 if len(segments) == 2 else 0), "话轮间隔非300毫秒")
    master = local_path(row["masterPath"], folder)
    require(local_path(manifest["masterPath"], folder) == master, "母版路径不一致")
    require(master.name == row["masterFile"], "母版文件名不一致")
    master_bytes = load_bytes(master)
    master_sha = digest(master_bytes)
    require(master_sha == row["masterStats"]["sha256"] == manifest["masterSha256"], "母版sha变化")
    pcm = read_pcm(master)
    assembled = array("h")
    gaps = []
    candidates = []
    for number, (planned, selected, recorded) in enumerate(zip(segments, row["segments"], manifest["segments"])):
        require(planned["id"] == selected["segment"], "选中候选话轮ID不符")
        for field in ("text", "speaker", "voice"):
            require(planned[field] == selected[field] == recorded[field], f"候选{field}与制作计划不符")
        for field in ("take", "speed", "steps", "expression"):
            require(selected[field] == recorded[field], f"候选{field}记录不一致")
        expected_speed = (min(1.12, planned["rate"] + 0.02)
                          if selected["take"] % 4 == 3 and not planned["breath"] else planned["rate"])
        require(abs(selected["speed"] - expected_speed) < 1e-6, "候选速度与计划及已知take规则不符")
        raw_path = local_path(selected["file"], folder)
        require(digest(load_bytes(raw_path)) == selected["sourceSha256"], "原始候选文件sha变化")
        metadata = load_json(raw_path.with_suffix(".json"))
        for field in ("segment", "text", "speaker", "voice", "take", "speed", "steps", "expression"):
            require(metadata[field] == selected[field], f"原始候选元数据{field}不一致")
        pcm_path = local_path(recorded["sourcePath"], folder)
        require(pcm_path == local_path(selected["pcmFile"], folder), "候选PCM路径不符")
        candidate_sha = digest(load_bytes(pcm_path))
        require(candidate_sha == recorded["sha256"] == selected["sha256"], "候选PCM的sha变化")
        original = read_pcm(pcm_path)
        if number:
            start = len(assembled)
            assembled.extend([0] * 7200)
            gaps.append({"startSample": start, "endSampleExclusive": len(assembled)})
        require(recorded["startSample"] == len(assembled), "候选起始采样错误")
        assembled.extend(original)
        require(recorded["endSampleExclusive"] == len(assembled), "候选结束采样错误或删词")
        require(recorded["candidateRecognition"] == selected["recognition"], "两处候选ASR记录不同")
        recognition = check_asr(recorded["candidateRecognition"], planned["text"], f"{key}/话轮{number + 1}")
        candidates.append({"text": planned["text"], "speaker": planned["speaker"], "voice": planned["voice"],
                           "sha256": candidate_sha, "file": str(pcm_path.relative_to(ROOT)),
                           "sourceSha256": selected["sourceSha256"], "take": selected["take"],
                           "rate": selected["speed"], "steps": selected["steps"], "candidateRecognition": recognition})
    require(manifest["gaps"] == gaps, "间隔采样记录不符")
    require(manifest["insertedGapSamples"] == 7200 * (len(segments) - 1), "间隔总长度错误")
    require(manifest["sampleRate"] == 24000, "manifest采样率错误")
    require(len(assembled) == len(pcm), "母版长度与完整源PCM拼接不符")
    source_peak = max(abs(sample) for sample in assembled)
    source_rms = math.sqrt(sum(sample * sample for sample in assembled) / len(assembled))
    require(source_peak > 0 and source_rms > 0, "源音频全静音")
    gain = min(3000 / source_rms, 27000 / source_peak)
    require(abs(gain - row["gain"]) < 1e-12 and row["gain"] == manifest["gain"], "整段gain不符")
    require(all(sample == round(original * row["gain"]) for sample, original in zip(pcm, assembled)),
            "逐采样不符：母版只允许源PCM拼接、300ms间隔与整段gain")
    peak = max(abs(sample) for sample in pcm)
    duration = len(pcm) / 24000
    require(0 < peak <= 27000 and 0 < duration < 60, "母版峰值/时长不合格")
    active = [index for index, sample in enumerate(pcm) if abs(sample) > 128]
    require(active and active[0] / 24000 < 0.7 and (len(pcm) - 1 - active[-1]) / 24000 < 0.9,
            "母版首尾静音过长")
    stats = row["masterStats"]
    require((stats["sampleRate"], stats["channels"], stats["sampleWidth"]) == (24000, 1, 2), "母版统计格式错误")
    require(stats["peak"] == peak and stats["byteSize"] == len(master_bytes)
            and stats["durationMs"] == round(duration * 1000)
            and abs(stats["durationSeconds"] - duration) < 1e-12, "母版统计值不符")
    wpm = len(spoken.split()) / duration * 60
    require(abs(wpm - row["wpm"]) < 1e-9, "语速统计未按实际朗读词数计算")
    require(plan["minimumWpm"] <= wpm <= plan["maximumWpm"], f"实际{wpm:.2f}词/分超出计划范围")
    master_recognition = check_asr(row.get("masterRecognition"), spoken, f"{key}/母版")
    return {"level": level, "questionId": key, "file": str(master.relative_to(ROOT)), "sha256": master_sha,
            "audioScript": script, "audioScriptSha256": digest(script.encode()), "spokenText": spoken,
            "spokenTextSha256": digest(spoken.encode()), "durationMs": round(duration * 1000),
            "wpm": round(wpm, 2), "voice": expected_voice, "candidateSegments": candidates,
            "masterRecognition": master_recognition, "peak": peak, "sampleRate": 24000,
            "channels": 1, "sampleWidth": 2, "gain": row["gain"], "gaps": gaps,
            "editPolicy": "逐采样核对完整源PCM、话轮间300毫秒静音及整段增益；无删词或后处理变速。"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", default=str(ROOT / "build/learning-primary456-20261011"))
    parser.add_argument("--partial", action="store_true", help="仅报告当前已通过段；有缺失也明确标记不完整")
    args = parser.parse_args()
    output = Path(args.directory).resolve(strict=True)
    require(output.is_relative_to((ROOT / "build").resolve()), "仅允许检查本仓库build目录")
    reports, failures, hashes = [], [], {}

    def load_bytes(path):
        data = path.read_bytes()
        hashes[str(path.relative_to(ROOT))] = digest(data)
        return data

    def load_json(path):
        return json.loads(load_bytes(path))

    for level, expected in LEVELS.items():
        level_start = len(reports)
        before_paths = set(hashes)
        try:
            folder = (output / level).resolve(strict=True)
            require(folder.is_relative_to(output), "年级目录越界")
            formal = load_json(AUTHORING / f"{level}-formal.astra.json")
            for name, expected_hash in formal["inputHashes"].items():
                require(Path(name).name == name, "作者稿哈希引用含路径")
                require(digest(load_bytes(AUTHORING / name)) == expected_hash, f"{name}输入哈希过期")
            scripts = {row["id"]: row["audioScript"] for row in formal["questions"] if row.get("audioScript")}
            require(len(scripts) == expected, "formal音频题数不是本批要求")
            production = load_json(folder / "production-plan.json")
            require(production["authoringSha256"] in formal["inputHashes"].values(), "计划未绑定当前已审稿哈希")
            if "deliverySha256" in production:
                require(production["deliverySha256"] == formal["inputHashes"][f"{level}-delivery.astra.json"], "计划delivery哈希过期")
            plans = index_rows(production["clips"], "production-plan")
            selected = index_rows(load_json(folder / "selection.json"), "selection")
            manifests = index_rows(load_json(folder / "manifest.json"), "manifest")
            require(set(plans) == set(scripts), "制作计划未精确覆盖formal音频")
            require(set(selected) <= set(scripts) and set(manifests) <= set(scripts), "selection/manifest有未知题号")
            for key, script in scripts.items():
                try:
                    require(key in selected and key in manifests, "缺少完整selection或manifest，未伪造缺段")
                    reports.append(verify_clip(level, key, script, plans[key], selected[key], manifests[key],
                                               folder, load_json, load_bytes))
                except (ValueError, KeyError, OSError, TypeError, wave.Error) as error:
                    failures.append({"level": level, "questionId": key, "reason": str(error)})
            # 生产可能同时进行，输入在核验期间变化则本年级全部不计通过。
            for relative in set(hashes) - before_paths:
                require(digest((ROOT / relative).read_bytes()) == hashes[relative], f"核验期间输入变化：{relative}，请重跑")
        except (ValueError, KeyError, OSError, TypeError, wave.Error) as error:
            del reports[level_start:]
            failures.append({"level": level, "reason": str(error)})
    complete = len(reports) == 19 and not failures
    result = {"date": "2026-10-11", "status": "完整19段通过客观核验，未作人耳或原生播放验收" if complete else "不完整：只列当前通过段，不能作为完整媒体审阅或发布依据",
              "complete": complete, "expectedCount": 19, "count": len(reports), "clips": reports,
              "failures": failures, "inputHashes": hashes,
              "normalization": "只归一大小写、标点、列明缩写、数字与1st；保留否定、词尾、所有格和币种，Mia不等价于me as。",
              "scope": "只读台词、哈希、声音映射、完整话轮逐采样拼接增益、独立双ASR正字法及计划语速核验；未合成或修改文件。"}
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if complete or args.partial else 1


if __name__ == "__main__":
    sys.exit(main())
