# 九年级长题面界面样本

`learning-junior3-preview.json` 是正式手编单元的公开题面快照，由服务端 `publicUnit` 白名单投影生成，仅打入 UI 测试包，不是 App 资源或正式题库。

每项的 `sourceHash` 对应原始完整单元规范哈希，`questionId` 指定本次检查的题目。当前取自三份 version 1 单元：

- Oliver 的 `bookclub-enquiries`：礼貌询问的三个长选项。
- Marcus 的 `neighbourhood-invitations`：三组完整句配对。
- Ruby 的 `reusable-cafe`：多词词块与双词填空。

更新快照时，读取 `Backend/config/learning/units/<id>.json`，经 `unitSchema` 校验后调用 `publicUnit`，保留原单元标题、水平和题面；使用 `contentHash` 记录原始单元哈希。不要复制 `answer`、`acceptedAnswers`、`acceptedOrders`、`answerPairs`、解析、审核材料或账号信息。不要把 UI 样本回填到正式题库。

测试只操作选中、配对、词块和输入状态，不调用判题或发奖接口。内容正误与计分链路另由服务端的逐题审核、事务测试和真实鉴权验收覆盖。
