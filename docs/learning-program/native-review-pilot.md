# 原生短复习切片验收

2026-09-16；WF-1.3；Debug 内存夹具，不是生产复习系统。

入口：`DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer Scripts/preview.sh build review`；已构建后可用 `preview review`。普通 App 导航和 Release 不提供此入口，账号不写入、无模型请求、无新增积分消耗。

原生 SwiftUI 路径：用户选择词义 → 开始所选小组 → 回忆 → 可选英文原句 → 揭示 → 三档自评 → 小结；支持提前结束、继续和撤销改评。调用已测试的 DomainKit 单会话投影，不另写一套计数规则。bank 提供两组释义验证显式选择，不把银行/河岸随便配上同一个来源句。

第一次截图发现背景干扰对比度、动态按钮标题重影。已增加背景遮罩和滚动底部空间，切换词/阶段回到顶部；原句按钮改成稳定标题与展开图标。使用既有收藏页背景，未生成或替换场景资产。

## 验证

- `Scripts/test-ui.sh -only-testing:LingoTripUITests/ReviewPilotTests` 最终 1 通过、0 失败、0 跳过；验证选择、揭示前无中文答案/原句翻译、撤销保留暴露、改评后仍计 1 个词。
- 最终证据：`build/DerivedData/VerificationResults/20260916T052250Z-27663.xcresult`。导出并目视检查揭示前截图，固定标题不再发生文字重叠。此前已查看改评和小结画面。
- 当前截图：`build/learning-program/review-pilot.png`（生成产物，不纳入提交）。
- 最终产物已用 `Scripts/preview.sh preview review` 安装并留在模拟器。

不把本次测试扩张为完整验收：真实收藏接入、持久化、历史统计、排程、音频、iPad/大字体/VoiceOver、真人理解仍未完成。自评标签与 FSRS 映射仍需单独决定；预览没有宣称自评即掌握。当前只验证了 iPhone 17 Pro 的指定原生任务路径。
