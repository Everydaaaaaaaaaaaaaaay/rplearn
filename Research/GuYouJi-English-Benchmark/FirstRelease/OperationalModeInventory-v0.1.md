# 首版结构模式查漏0.1

从[当前117配对源](paired-source-overview-v0.6.json)和[47/294作者包](combined-review-index-v0.17.json)逐成员派生[结构清单](operational-mode-inventory-v0.1.json)，得到67个年级×任务×响应数×选项数/篇数/关键输入形式组合：40有同结构作者示例、27尚无。67只是本批明确的归并口径，非全国题型数量或新增验收配额；有同结构例子也不覆盖所有体裁、能力或难度。

| 年级 | 已观察结构组合 | 有作者示例 | 尚无示例 | 配对源组 |
| --- | ---: | ---: | ---: | ---: |
| 7 | 16 | 9 | 7 | 17 |
| 8 | 18 | 8 | 10 | 32 |
| 9 | 13 | 7 | 6 | 17 |
| 10 | 7 | 4 | 3 | 18 |
| 11 | 7 | 6 | 1 | 15 |
| 12 | 6 | 6 | 0 | 18 |

| 缺口ID | 年级／任务／响应／每题选项 | 关键形式 | 源组 |
| --- | --- | --- | --- |
| opmode03 | 7／选项完形／10／4 | {} | g7.2019.cloze |
| opmode04 | 7／篇章形式／4／不适用 | {"materials": 1, "subgroup_slots": null, "response_policy": "given_only_unrestricted"} | g7.xicheng2025.optionalGrammar |
| opmode05 | 7／音标词补全／4／不适用 | {"response_limit": "not_explicit"} | g7.xicheng2025.phonetic |
| opmode09 | 7／选择阅读／3／3 | {"input": "text"} | g7.xicheng2025.optionalReading |
| opmode10 | 7／选择阅读／4／3 | {"input": "text"} | g7.xicheng2025.readingB, g7.xicheng2025.readingC |
| opmode12 | 7／单句选择／10／3 | {} | g7.xicheng2025.language |
| opmode13 | 7／整句翻译／3／不适用 | {"required_cues": true} | g7.xicheng2025.translation |
| opmode17 | 8／选项完形／8／4 | {} | g8.2025fengtai.cloze, g8.fengtai2026.cloze |
| opmode19 | 8／选项完形／10／3 | {} | g8.changjun2024.cloze |
| opmode20 | 8／开放读答／4／不适用 | {"points": [2, 2, 2, 4], "last_operation": "action_plus_reason"} | g8.bnu2026.readingResponse |
| opmode21 | 8／开放读答／4／不适用 | {"points": [2, 2, 2, 4], "last_operation": "opinion_plus_two_reasons"} | g8.fengtai2026.readingResponse |
| opmode22 | 8／开放读答／5／不适用 | {"points": 2, "last_operation": "source_specific_reading_response"} | g8.changjun2024.readingAnswer |
| opmode23 | 8／篇章形式／4／不适用 | {"materials": 1, "subgroup_slots": null, "response_policy": "given_only_unrestricted"} | g8.bnu2026.optionalGrammar |
| opmode24 | 8／篇章形式／10／不适用 | {"materials": 1, "subgroup_slots": null, "response_policy": "ungiven_one_given_form"} | g8.changjun2024.grammar |
| opmode25 | 8／需求匹配／3／不适用 | {"cards": 4, "input": "images"} | g8.fengtai2026.imageMatching, g8.bnu2026.imageMatching |
| opmode26 | 8／需求匹配／3／不适用 | {"cards": 4, "input": "text_cards"} | g8.2025.matchingA, g8.2025fengtai.matchingA |
| opmode31 | 8／单句选择／10／4 | {} | g8.bnu2026.sentenceChoice |
| opmode36 | 9／选项完形／10／4 | {} | g9.suzhou2024.cloze |
| opmode37 | 9／语境单词补全／8／不适用 | {"response_limit": "one_word", "cues": ["Chinese_meaning", "initial_letter"]} | g9.suzhou2024.singleVocabulary |
| opmode40 | 9／篇章形式／10／不适用 | {"materials": 1, "subgroup_slots": null, "response_policy": "ungiven_one_given_form"} | g9.suzhou2024.grammar |
| opmode42 | 9／选择阅读／4／4 | {"input": "text"} | g9.suzhou2024.readingB, g9.suzhou2024.readingC, g9.suzhou2024.readingD |
| opmode43 | 9／选择阅读／5／4 | {"input": "table_and_text"} | g9.2025.readingA |
| opmode46 | 9／共享衔接／5／不适用 | {"shared_options": 5} | g9.2025.insertionE |
| opmode48 | 10／选项完形／10／4 | {} | g10.2024.cloze |
| opmode50 | 10／篇章形式／10／不适用 | {"materials": 1, "subgroup_slots": null, "response_policy": "ungiven_one_given_form"} | g10.2025yearend.grammar, g10.wenzhou2025.grammar |
| opmode52 | 10／选择阅读／3／4 | {"input": "text"} | g10.2024.readingA, g10.2024.readingC, g10.2025yearend.readingA, g10.wenzhou2025.readingA |
| opmode59 | 11／选择阅读／3／4 | {"input": "text"} | g11.2024.readingA, g11.spring2024.readingA |

优先补核心结构：高一单篇十空语法、三题四选阅读、十空四选完形；高二三题四选多简介；初二八空四选与十空三选完形；初三十空四选、给词不限一词语法、四题四选；初一四题三选/单句三选。其余选做、音标、不同短答构念、具体图匹配与整句任务继续留缺口，不能用其他年级同响应方式替补。此优先级是首版工程顺序，非称其他结构不重要。

分篇3/3/4与4/3/3保留；全部一词与仅无提示一词分开；图片匹配不被文字卡片替代；5共享项不被7共享项替代；开放末问行动＋理由与观点＋两个理由分开。genre不进入当前签名，人物/书评/论证的操作仍需另审。共享衔接标题/句子/条件分句在逐题协议层区分，不因签名相同视为等功能。

47作者中44锚定117内来源，另3为初二模拟篇章和高一邮件/续写；这3完整作者仍保留，不伪造117内源键。当前库有40结构示例不等40经模型/教师/学生验证；17本机控制也不能代表40种模式均支持模型。首版完成条件与长期范围继承README/Acceptance，不能单凭全部数量通过。
