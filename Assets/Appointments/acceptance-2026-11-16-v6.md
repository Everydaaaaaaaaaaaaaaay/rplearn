# 赴约界面 v6 实装验收

2026-11-16，用户采用 [v5 原生方案预览](acceptance-2026-11-16-v5-preview.md)后接入正式赴约流程。模拟器范围内自检通过。

## 实装范围

- 正式回顾页使用连续暖白正文、148pt 实景横幅、22pt 标题、角色头像、爱心好感图标、用户行动头像和书签记忆图标。Debug 方案入口复用同一正式回顾组件。
- 列表、历史和照片来源采用同一横幅与连续排版。阅读页复用真实角色头像，保留实景轮播、查词、朗读、行内输入及充足留白。
- App 装配层传入既有角色 `CharacterCard` 快照，头像复用 `AvatarBadge` 的本地资源和远程缓存。用户头像沿用账号环境中的 `UserAvatar`。切换账号时清除约定人物快照，异步加载回写检查账号与任务状态。
- 好感持平、减少、小幅变化、待结算及重试使用实际结果。记忆按实际保存、编辑、遗忘、更新等状态显示。原始选择、结果与完整经历可读取、复制和回看。

## 摄影与视觉复验

三张伦敦照片的原图、许可和哈希沿用 v5 及其引用记录，G0–G3 证据沿用。实装横幅采用原生确定性裁切。标准屏逐图核对列表、阅读、输入、回顾、历史和来源，补充窄屏输入及不同结算状态检查，G4/U1 在本记录范围内通过。

标准设备为 iPhone 18 Pro，402×874pt，覆盖标准和最大辅助字号。窄屏为 iPhone SE 3，375×667pt。正式字体随系统字号缩放，时间在辅助字号下使用纵向排版。

原生截图及导出 manifest 位于 `build/appointment-production-2026-11-16/standard/` 和 `compact/`。展示页为 `build/appointment-style-2026-11-15/index.html`，保留六张主设备原图，逐图 SHA256 位于 `build/appointment-production-2026-11-16/screenshots.json`，HTTP 链接与字节哈希复核通过。

## 验证证据

| 检查 | 结果与结果包 |
| --- | --- |
| 标准屏定向 UI | 6 项通过，0 失败，0 跳过。包含完整赴约、双语输入、续读、只读回看、原命令重试、最大辅助字号及持平／减少／待结算。`20261116T075836Z-65143.xcresult` |
| 窄屏完整流程 | 1 项通过，0 失败，0 跳过。`20261116T080724Z-66553.xcresult` |
| 最终预览返回回调 | 1 项通过，0 失败，0 跳过。正式回顾组件与 Debug 预览共享布局，预览返回活动入口成功。`20261116T081511Z-67907.xcresult` |

结果包位于 `/Users/tiantian/eng/build/DerivedData/VerificationResults/`。模型、缓存和命令实现的既有单元证据沿用 v4 的 11 项通过记录。本次编译、`Scripts/check-architecture.sh --ios` 和 `git diff --check` 通过。UI 测试的滚动定位依据实际内容区域，适配固定照片横幅。

已通过 `Scripts/preview.sh preview appointments-preview` 安装最新版，主设备模拟器停留在可直接赴约的列表。最终安装画面保存为 `build/appointment-production-2026-11-16/installed-final.png`，已查看原图。磁盘空间不足曾阻止保存，清理可再生成的编译缓存后重试成功。

Computer Use 两次连接均返回 `codex app-server exited before returning a response`，本轮交互依据原生 UI 自动化，视觉依据实际截图核对。真机、在线头像下载与实时模型生成未新增实测。
