# 研究尝试0.3：排序序列和配对选择

[Schema0.3](AttemptTrace-v0.3.schema.json)保留0.2全部作答类型和逐题修订链，增加排序与配对的私有payload。0.1、0.2文件和样例不改写，旧版本不能偷接收新payload。题组合同0.1至0.3本来已有ordering/matching定义；此前Unit3缺口中的宽泛措辞应理解并修正为“实际作答记录缺少相应payload”，不能声称题组没有这些定义。

排序保存`kind=ordering`和有顺序的`ordered_element_ids`。ID来自冻结题目elements，不能重复或引用外部成员；顺序不能排序归一化。部分序列、空序列和完整但排错的序列都能保存，它们是实际编辑后的响应，不是正确性结论。完整排列要求和参考序列由评分处理；已有题组可列多条accepted_orders，仍不能自动推出教材中模糊频率表达的唯一次序、并列规则或百分比刻度。

配对每条answer事件的item_id就是左侧成员，payload保存`kind=matching`和一个`right_option_id`。ID只来自这道左侧题的right_options；null表示进入过但未赋右侧选项。显式skip仍要求整个payload=null，与未赋值的配对payload不同。不在payload另写可冲突的left_item_id。尽管冻结题目可规定右侧不可复用，作答记录仍保存用户错误复用的情况，由评分判断，而非丢弃这份真实错误。

两份原创合成记录同时包含排序、配对、改答和跳过后重新答；一份有作者定义的两种等价排序/配对键，另一份键为unknown。它们不是Unit3题干的改写、教师答案或语言难度锚定集。20项拒绝反例核查成员/选项引用、格式伪装、私有评分混入、版本、修订和未知键；另确认所有四份0.2payload能在0.3记录、错误/部分/空排序及错误复用配对仍可保存，报告不回显新payload。

运行：

```sh
python3 Research/GuYouJi-English-Benchmark/Tools/check_attempt_relations_contract.py
python3 Research/GuYouJi-English-Benchmark/Tools/validate_attempt_traces.py Research/GuYouJi-English-Benchmark/Attempts/Fixtures-v0.3/*.json
```

本地jsonschema运行时见`Storage/SchemaRuntime.md`。新版本没有实现判分、用户端、网络重试、签名或真实时钟。整组提交只证明每题已有显式answer/skip事件，不保证响应完整、正确或完成口头动作；first_response_event_ids遇首次skip也会指向该事件，不能自动当成首次已答表现。

Unit3的圈词与排序、重音匹配与角色扮演仍包含多个动作；音频/图式完整语义关联、顺序方向的类型化、部分顺序评分、共享表格关系、学习者导图、录音和交互轮次继续缺失。取得官方键、独立复核、服务隐私和真实学生试做前，相应完整导入与生产准入仍为false。
