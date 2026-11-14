# Debug 真机正常入口接入 v6

2026-11-14，Codex 自检。本版修复用户报告的「build 到手机后活动仍为旧版」问题。场景照片与透明描边按钮沿用 [v5](acceptance-v5.md)，本版修改 App 路由与当前城市读取。

## 原因与改动

旧实现仅通过 `scenes-preview` 打开十五城场景。正常活动路由依赖 `activity-world-release.json`，该正式清单仍未生成，正常启动会进入旧活动界面。

Debug 构建在正式清单尚未配置时，首页「城市活动」现使用新版场景视图，读取已登录账号的 `currentRegionID`。此入口固定显示当前城市，可返回首页后重新进入。专用素材预览继续提供十五城切换，伦敦实际外出样板与既有社交测试夹具继续使用各自服务。

正式世界仍在草稿阶段。当前 Debug 场景按钮展示剧情准备提示，完整 NPC 内容及 Release 正式发布按原重构计划继续。

## 验证

- `build/DerivedData/VerificationResults/20261114T074137Z-51891.xcresult`，正常首页入口回归 1 项通过。通过首页按钮进入，验证账号纽约对应高线公园与中央车站，验证固定当前城市、返回首页、再次进入。未使用 `scenes-preview` 启动。原生截图在 `build/ActivityWorldPhotos/normal-entry-v6/`。
- iOS 架构、diff 与文档链接检查通过。原图、空间、许可、哈希、全屏裁切与按钮大小屏视觉证据沿用 v2–v5。
- 复用 Xcode 现有真机 DerivedData 构建 Debug 成功，签名 Team 与 Bundle ID 沿用已安装应用。通过 `devicectl` 安装到连接的 iPhone 13，并以正常环境启动成功。
- Device Hub 已观察真机启动后的首页。镜像坐标点击返回 `windowNotFoundAtPosition`，真机进入活动页的自动交互未完成，正常入口交互证据来自上方模拟器测试。
- 已通过 `Scripts/preview.sh preview home` 安装最新模拟器构建，供从普通首页入口复核。

## 边界

本版完成 Debug 普通活动入口与装机修复。真机活动页实际点击及用户复核待完成，完整相遇世界、历史人物设定迁移与正式发布状态仍见重构进度。
