# 成人生活剧情首批 v2 · 验证记录

2026-10-31。首批接入五篇修订稿，三个新增候选尚未增加正式入口。版本源、逐场内容和镜头决定见 [生产记录](../../Content/AdultLife/2026-10-31/README.md)。

## 当前范围

正式目录仍为五站主线、十五篇城市故事。五个入口提供独立的 v2 阅读资源，旧版保留给已有进度；目录和服务端奖励 ID 保持原值。v2 合计 277 个节点，含 15 个选择点、20 条完整路径。换算整个当前目录为 703 个节点、56 条路径；这不包含保留的旧版副本，也不把配音样板计为剧情。

本次叙事加深不是增加抽象感悟：Ruby 从反复清理同一片海滩追问垃圾来源；Marcus 需要承认自己误报了时间；Mei 可以不向所有人公开告别；聚餐的劳动和费用可由不同人自愿承担；维修桌的共享时间使帮助有实际限度。墨尔本咖啡与海湾、纽约唱片工作和街角、新加坡熟食中心、多伦多公寓聚餐、奥克兰海港社区分别进入行动与节奏。

## 自动检查

- `python3 Tools/ContentPipeline/build-adult-life-stories.py --check`：五个运行资源与固定文稿、编排决定一致；65 字符预算成立。
- `Scripts/check-architecture.sh --ios`：通过。未增加 Feature 之间的依赖。
- `Scripts/test.sh` 定向运行 `AdultLifeEpisodeTests`、`StoryProgressStoreTests`、`StoryExperienceContextTests`、`PromptBuilderTests`、`DepartureCollectionTests`：31 通过、0 失败、0 跳过。覆盖原目录、新版二十条路径每页恢复、首次经历防重玩覆盖、旧断点保留、目录完成投影和遗忘后不召回。
- 测试证据：`build/DerivedData/VerificationResults/20261031T045803Z-18031.xcresult`。前一轮编译中修正过测试宏直接调用 mutating 方法的问题，最终结果以上述成功证据为准。
- `Scripts/test-ui.sh -only-testing:LingoTripUITests/AdultLifeStoryTests/testNewEditionDeclineAndResume`：1 通过、0 失败、0 跳过。实际从稳定旧入口进入新版，选择离开、终止进程、恢复新版断点，再选择不定日子到结尾，并检查未串入留下线的吐司对白。
- 界面证据：`build/DerivedData/VerificationResults/20261031T050013Z-19044.xcresult`，含 Ruby 拒绝后结尾截图。
- 最后修正多伦多点餐镜头后，重跑 `AdultLifeEpisodeTests`：3 通过、0 失败、0 跳过，证据为 `build/DerivedData/VerificationResults/20261031T051600Z-23890.xcresult`。首轮重跑因磁盘空间不足中断打包，下一轮遇到中断产物的签名校验失败；清理可重建的 Xcode 缓存及损坏的打包产物后通过，未删除用户存档、数据库或测试证据。

## 模拟器与视觉

使用当前已启动的 iPhone 18 Pro，iOS 27.0，设备 `659893A7-0822-43F4-8DA1-4A92E9C78814`，不新建模拟器。工作树原绑定设备在本机不存在，因此本次所有命令显式使用这个设备，不改动本地绑定。

Computer Use 读取 Device Hub 返回 ScreenCaptureKit `-3811`，未能进行原生交互检查。采用定向 UI 测试验证选择与跨进程恢复，并以 `simctl` 只读截图检查最新构建的页面。已通过 `Scripts/preview.sh build home` 安装最新源码构建；逐一打开五个稳定入口，等待加载完成后截图。最初过早截到的启动底色已重新截图，不计为已检查页面。

五个新版首屏均正常显示本地段落标题、专属城市舞台、双语正文、查词提示和继续入口；没有观察到正文或底部操作遮挡。Ruby 结尾的 UI 测试附件也已查看：两个真实选择的回顾、完成与重玩入口均可读。

最终镜头修正后再次运行 `Scripts/preview.sh build home` 成功；构建包内五个 v2 JSON 与源资源逐字节相同。模拟器留在 Ruby 新版首屏，声音关闭，`final-ruby-preview.png` 已查看，正文与继续操作显示正常。

截图位于 `build/Verification/adult-life-20261031/`，不把生成的构建截图纳入源代码提交。版本定位（PNG SHA-256 前十二位）：

| 截图 | 哈希 |
| --- | --- |
| ruby-opening.png | `0d087d7e131e` |
| newyork-opening.png | `145cd69991b7` |
| singapore-opening.png | `8d6d83a02bc3` |
| toronto-opening.png | `fb053cea1b68` |
| auckland-opening.png | `e01cde1ade5d` |

画面文件未改动。已检查原版咖啡馆/申请、纽约午餐/夜间消息、Mei 晚饭/持机画面、多伦多公寓/厨房/订单/甜点、奥克兰维修桌，按新路径排除不成立的成果或拍照构图。多伦多点餐结尾改为先显示订单、再切回公寓，排除“蛋糕尚未切开”时已经吃蛋糕的原甜点图。它们是预写故事的手绘舞台快照，不声称是一段连续动作影片；桌面食物等静态道具不随每句台词逐帧变化。

## 验证边界

没有后端变更、生产部署或商店发布；没有调用真实在线模型评测。关系奖励继续走既有幂等接口，本轮新增的路径经历使用既有剧情同步载荷，不添加新的生产数据库字段。

聊天承接的确定性输入、身份过滤、拒绝与未确认日期、遗忘和重玩已用单元测试验证；模型是否在真实长期聊天中持续自然地表达，还需要另行线上样本，不以提示词通过代替实际生成质量。

新版配音使用现有本地合成路径。本次未新增预制录音、环境录音或配乐，没有逐句听音验收，也没有真机性能验证。已有二十篇原版预制音频仍保持原字节与绑定。

八篇准备稿仍是独立的作者审阅材料：首批五篇在生产编排中补充地方细节和停顿，另外三篇需要独立场景资产和入口后再接入；Marcus 三次接触的后续小稿本次仅提供事实承接，没有自动发起下一场赴约。
