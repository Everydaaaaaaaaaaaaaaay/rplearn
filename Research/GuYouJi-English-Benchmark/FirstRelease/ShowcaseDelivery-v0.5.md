# 初高中多题型效果0.5

接续[0.4](ShowcaseDelivery-v0.4.md)，在同一效果页增加四个已有完整完形，支持同年级、同题型下的多组选择。入口仍是`http://127.0.0.1:8766/build/english-benchmark-showcase/index.html`；重建：

```sh
python3 -B Research/GuYouJi-English-Benchmark/Tools/build_school_showcase.py --output build/english-benchmark-showcase
```

当前32完整组/228作答位，其中四新展示组为初一6空3选、初二8空4选、初三10空4选和高一10空4选。原28组194回应的规范化JSON载荷与提交前版本2429db37一致，SHA256为`31a6a2d27f9b1f47ff1a52a117a80f4b04537036d559c929dd7a96d260602d6a`。原初三10空3选、高一15空4选保留，不能用展示入口统一题型体量。

共709逐题展示选项位置（含共享候选在各响应界面的呈现，不作为709独立候选素材）、50参考形式空、37共享候选条目、9开放/写作响应和10输入框；两段续写仍是一个任务。新四组含130逐题候选，正文、全部空和全组作者依据均完整显示。查看解析后可展开完整作者稿，包括回填和质量边界。

37结构/负例控制及11实际浏览器交互记录保存在研究缓存并登记处理记录；实际检查漏答、四完整向量、同题型组间保存/隔离、原15空、重置及单组隐藏，窄屏入口已目视核验。未调用模型，未部署后端或修改iOS；本机展示不证明学生难度、商用、独立教研或生产适配。全部作者稿53组/338回应不增，还有21组110回应未在本页展示。

见[选择清单](showcase-selection-v0.5.json)、[标准0.52](PracticalAuthoringStandard-v0.52.md)及[本批研究](../Studies/2026-10-15-variable-cloze-complete-showcase-and-group-routing.md)。旧展示选择和交互证据保留。
