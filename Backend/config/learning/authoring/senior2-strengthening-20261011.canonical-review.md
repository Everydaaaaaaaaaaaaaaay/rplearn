# 高二强化稿正式结构适配记录

2026-10-11。范围仅本目录高二强化稿的 canonical、formal-review、goals 和本记录四个隔离文件；未改正式 catalog、bank、units，未提交或部署。逐题阅读原作者稿、自审、主审记录及正式内容/判题合同后亲写适配；程序只保存、核对既有字符串和运行校验，没有组合或模板生成教学内容。

## 保留与适配

18题保留全部作答材料、三篇独立阅读材料、所有候选、词块、配对多余项、原合法答案、两段听力脚本与解析。三段完整双语故事均在题前，afterQuestion=0。新增简短操作说明和不直接给出答案的提示；原作者目标、难度、自审解题路径与来源细节不冒充客户端提示。难度说明逐题沿用作者review.difficulty。主审核对实际LearningClozeControls只支持按钮点选后，将q15 instruction改为“选择词块填两空，每个词块至多使用一次。”，prompt末句改为“选择最合适的衔接词。”；仅修正操作文案，英文材料、候选及答案不变。

q15/16原稿已使用共享词库和正式slotId/tokenId映射，没有独立词库转共享的机械并集操作。逐空人工审核每个候选及完整组合：q15仅s1-b/s2-c保留替代与结果；q16仅s1-c/s2-a保留仍进行的维修与已完成安装数量。四个候选各自保留，无改词、删词或新增干扰。q13/14仍是三配四且r3多余。

## 一处经主审确认的答案边界修正

q10原稿只收 `avoiding dragging the chairs across it`，但题面只要求the chairs不用代词，未要求地板必须用it。把作者review中的隐含it限制当题面规则会误判。经主代理2026-10-11明确确认，canonical增加：

- `avoiding dragging the chairs across the old floor`
- `avoiding dragging the chairs across the floor`

两个新增变体都保留avoid/drag的-ing形式、原椅子宾语及同一地板。解析、歧义审核和正确probe同步补充。原astra稿保持为原始作者证据，不能再以其单一acceptedAnswers否认这两个变体。q08、q09各一个规范文本答案，另检查大小写、空格与句末标点归一。

后续主审明确本题是受控-ing句式，将题面要求写为“沿用the chairs和介词across，不用代词替换the chairs”。保留上述三种地板指称。`avoiding dragging the chairs over it`在自然改写中可有合理解释，但不满足当前显式across支架；新增一个完整负probe只验证这一任务边界，解析不泛称over为英语错误。

q11、q12各保留一个完整顺序；q12前移in the library会改变对学生或邀请地点的附着，主审确认不新增。配对接受答案对传输顺序变化；这是同一语义映射，不是第二种配对解。

## 逐题审核与验证

formal-review为18题分别记录独立上下文、歧义边界、候选依据及完整合法正误probe。选择题含所有四个选项；配对错误probe仍覆盖全部左项且不重复右项；cloze错误probe仍填满两槽且使用合法不同词块，不把缺字段/非法答案异常充作错误判分证据。

采用Node v24.19.0与项目tsx，调用真实 `questionSchema`、`unitSchema`、`answerSchema`、`gradeAnswer`、`contentHash`：

- 16道文字题通过questionSchema；去掉两道媒体待补题及其专属goalIds后的文字投影通过unitSchema。
- 66个probe全部符合预期：25个正确、41个错误。文字58个；听选脚本文字逻辑8个，后者不是媒体验收。
- goals两条符合正式目标记录结构；formal-review依据catalog.ts的正式review字段规则校验通过。
- 全文、选项、词块、故事、脚本、原答案集合按字段核对；q10获准增加两变体、显式across支架与解析补充，q15末句只将拖入改为选择以符合实际按钮操作，其他解析逐字保留。
- review真实绑定canonical内容哈希 `50579f4d6ded4b46378adbdec3f51f5497256169c9334befdce5f4c6727018df`。这是内容哈希，不是媒体哈希；q15操作文案及q10显式支架修订后重算，并重新执行全部66个probe。

本轮验证命令（临时校验器仅验证，不生成教学内容）：

```sh
PATH=/Users/haruhi/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin:$PATH node Backend/node_modules/tsx/dist/cli.mjs /tmp/lingotrip-s2-strength-validate.mts
git diff --check -- Backend/config/learning/authoring/senior2-strengthening-20261011.canonical.json Backend/config/learning/authoring/senior2-strengthening-formal-review-20261011.json Backend/config/learning/authoring/senior2-strengthening-goals-20261011.json Backend/config/learning/authoring/senior2-strengthening-20261011.canonical-review.md
```

## 来源与待主审事项

两项待登记目标为 `s2.discourse-reference-scope`、`s2.integrating-conditions`；sourceIds/level/canDo/boundaries依据原作者实际核读记录，明确本次未新查教材。既有社区存档版次、全册哈希及教材音频未被本轮复核，不能声称出版社本轮下载或全年覆盖。现有目标不重复登记。

q17/18仍为pending，仅保留脚本，无assetId或媒体哈希；q18须两声可辨且不朗读A/B标签。完整canonical故意不能通过unitSchema，不能进入正式发布。formal-review的approved仅是文字作者自审，不是完整单元或媒体批准；补媒体后须重算哈希并复核。

主代理仍须确定正式混编互斥：q06/13共享条件核对策略；q04/14/17共享来源意识；关系从句、过去完成、衔接词可能接受旧题反馈支架。未运行实际插槽组卷，不以字符串不重复推断没有泄漏。媒体制作及独立核听、原生18题连续作答、真人难度与学习成效仍未验证。
