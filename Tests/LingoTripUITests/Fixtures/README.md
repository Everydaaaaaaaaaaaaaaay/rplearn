# 九年级长题面界面样本

`learning-junior3-preview.json` 是正式手编单元的公开题面快照，由服务端 `publicUnit` 白名单投影生成，仅打入 UI 测试包，不是 App 资源或正式题库。

每项的 `sourceHash` 对应原始完整单元规范哈希，`questionId` 指定本次检查的题目。当前取自三份 version 1 单元：

- Oliver 的 `bookclub-enquiries`：礼貌询问的三个长选项。
- Marcus 的 `neighbourhood-invitations`：三组完整句配对。
- Ruby 的 `reusable-cafe`：多词词块与双词填空。

更新快照时，读取 `Backend/config/learning/units/<id>.json`，经 `unitSchema` 校验后调用 `publicUnit`，保留原单元标题、水平和题面；使用 `contentHash` 记录原始单元哈希。不要复制 `answer`、`acceptedAnswers`、`acceptedOrders`、`answerPairs`、解析、审核材料或账号信息。不要把 UI 样本回填到正式题库。

测试只操作选中、配对、词块和输入状态，不调用判题或发奖接口。内容正误与计分链路另由服务端的逐题审核、事务测试和真实鉴权验收覆盖。

`learning-senior1-formal-practice.json` 是 `expansion.20261024.senior1.packing-and-printing-152` 的公开题面快照，取自
`Backend/config/learning/expansions/2026-10-24/b152.json`，原始单元 contentHash 为
`7d3732f7c0d261d21d9333df33e7bffdb1c56268339dff203dbd9c733e09fd29`，快照 SHA-256 为 `897a17722ca06902dd74347f20638405c7cd8ca8e6701a933e48fa55012494e4`。
用于检查真实测试入口所复用的正式页面：五空七选项整篇作答及后续十空语法填空。
快照不含答案或解析；测试不向真实账号提交成绩。

`learning-senior2-clean-reading.json` 是 `gaokao.authored.senior2.77a6034221f54d3b` 的公开题面，用于复现阅读页 B1 重复标题和紧凑答题面板，来源 `Backend/config/learning/gaokao/authored.json`。快照 SHA-256：`8bba2e9b37b998063ab2bec4ab875e4c7681a67f27885ca1eefe605498dfc694`；不含答案、解析或账号数据。
