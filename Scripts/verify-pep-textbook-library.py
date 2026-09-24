#!/usr/bin/env python3
"""校验人教版教材参考库的结构、册次和证据边界。"""

import json
from pathlib import Path
from urllib.parse import urlparse


ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "docs/learning-program/textbooks/pep/catalog.json"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def official_url(value: str) -> bool:
    parsed = urlparse(value)
    return parsed.scheme == "https" and parsed.hostname in {
        "www.pep.com.cn",
        "www.moe.gov.cn",
        "jc.pep.com.cn",
        "book.pep.com.cn",
    }


def verify() -> None:
    data = json.loads(CATALOG.read_text())
    volumes = data["volumes"]
    require(data["schemaVersion"] == 1, "教材库格式版本不支持")
    require(data["volumeCount"] == len(volumes) == 12, "教材册次不完整")
    expected_junior = {(7, "upper"), (7, "lower"), (8, "upper"), (8, "lower"), (9, "upper")}
    expected_senior = {("mandatory", n) for n in range(1, 4)} | {
        ("selective-mandatory", n) for n in range(1, 5)
    }
    seen_ids: set[str] = set()
    junior: set[tuple[int, str]] = set()
    senior: set[tuple[str, int]] = set()
    audio_count = 0
    unit_count = 0
    for volume in volumes:
        identity = volume["id"]
        require(identity not in seen_ids, f"重复册次：{identity}")
        seen_ids.add(identity)
        require(not volume["fullTextReviewed"], f"全文核对状态需要人工证据：{identity}")
        require(official_url(volume["source"]["url"]), f"来源不是官方 HTTPS 链接：{identity}")
        ebook = volume["officialEbook"]
        require(official_url(ebook["catalogUrl"]) and official_url(ebook["readerUrl"]), f"电子教材入口无效：{identity}")
        require(ebook["readerUrl"].endswith("/mobile/index.html"), f"电子教材应使用 HTML5 阅读入口：{identity}")
        require(ebook["publisherListingTitle"].strip(), f"缺少人教社登记书名：{identity}")
        require(ebook["contentReview"] in {"sample-page-reviewed", "not-reviewed"}, f"教材阅读状态无效：{identity}")
        numbers = [(unit["number"], unit.get("starter", False)) for unit in volume["units"]]
        require(len(numbers) == len(set(numbers)), f"重复单元编号：{identity}")
        require(all(unit["title"].strip() for unit in volume["units"]), f"单元题名为空：{identity}")
        unit_count += len(numbers)
        if volume["stage"] == "junior":
            junior.add((volume["grade"], volume["term"]))
            require(volume["edition"] == "2022-curriculum-revision", f"初中版次不符：{identity}")
            require(volume["coverage"] == "unit-titles-and-public-audio-links", f"初中证据状态不符：{identity}")
            for unit in volume["units"]:
                require(unit["audioResources"], f"缺少公开音频：{identity} {unit['title']}")
                for resource in unit["audioResources"]:
                    require(resource["label"].strip() and official_url(resource["url"]), f"无效音频入口：{identity}")
                    audio_count += 1
        elif volume["stage"] == "senior":
            senior.add((volume["track"], volume["bookNumber"]))
            require(volume["edition"] == "2019", f"高中版次不符：{identity}")
            require(volume["coverage"] == "unit-titles-in-official-lesson-index", f"高中证据状态不符：{identity}")
            for unit in volume["units"]:
                require(official_url(unit["titleEvidenceUrl"]), f"单元缺官方证据：{identity} {unit['title']}")
                require(unit["exampleListedActivity"].strip(), f"单元缺课例活动样本：{identity} {unit['title']}")
        else:
            raise ValueError(f"未知学段：{identity}")
    require(junior == expected_junior, "初中册次缺失或混入未核对册次")
    require(senior == expected_senior, "高中册次缺失")
    require(unit_count == 78, "单元数量与已核对目录不一致")
    require(audio_count == 288, "初中音频入口数量与已核对页面不一致")
    print(f"教材库校验通过：{len(volumes)} 册、{unit_count} 个单元、{audio_count} 个官方音频入口")


if __name__ == "__main__":
    verify()
