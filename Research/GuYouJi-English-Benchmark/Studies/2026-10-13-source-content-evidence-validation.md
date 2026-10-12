# 非空、已解析的来源内容证据

本轮发现研究题组原来的来源检查仅要求 acquisition 有 path。因此，已经登记的屏东学校文章空白 HTTP 200 文件也可能被题组引用为内容证据。这不能证明取得过题文，现已收紧两版合同共同使用的语义校验器。

## 校验规则

- 来源与取得记录身份必须存在，且取得记录属于该来源。
- 取得状态必须是 fetched_unreviewed 或 derived_unreviewed；bytes 是正整数，摘要是64位小写十六进制，并有路径。
- 文件格式须属于校验器明确支持的解析类别。not_checked、bytes_and_digest_only、仅 gzip 传输校验、未知标签均不能成为内容引用。可保留在取得登记中供后续处理。
- `--check-assets` 同时验证来源内容位于 ignored build 缓存、文件存在、实际大小和 SHA-256 相符。未启用时只检查登记元数据，不能证明文件仍在本地。

这些规则只验证引用与文件保存条件。PDF解析、MP3容器解析等不证明题目正确、音频内容一致、权限允许、独立复核完成或适合目标学习者。结构性测试夹具引用实际文件只是验证来源关联的演示，不声称夹具内容源于该试卷。

## 验证

八份原创夹具、原有45个反例与新增16个来源反例通过；实际屏东候选PDF引用通过，实际学校文章空响应引用拒绝。反例包括状态、零大小、布尔大小、未解析/未知格式、坏摘要、源归属、缺文件、缓存外路径和本地大小/摘要变化。保留合同0.1读取，不改历史题文。

执行：

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=build/english-benchmark-research-20261012/python-libs /Users/tiantian/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 Research/GuYouJi-English-Benchmark/Tools/check_item_group_contract.py
```

G05仍开放。合同校验不是正式出题或生产评分许可；独立/学习者证据、完整原卷配套、内容与媒体语义核验仍待完成。
