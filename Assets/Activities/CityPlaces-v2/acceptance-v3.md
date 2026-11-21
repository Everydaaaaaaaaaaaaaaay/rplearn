# 十五城全屏活动入口 v3

2026-11-14，Codex 自检。本版改动场景入口布局与交互，照片继续使用 v2 的 54 张当地实拍。本机预览可交付，正式世界保持草稿，真机及用户验收待完成。

## 版本与沿用证据

原图、出处、作者许可、SHA256、地理核对与空间观察沿用 [v2 选图](selected-photos.json)及[v2 记录](acceptance-v2.md)。本版复核全屏裁切、文本与操作区域。素材字节与横向对齐配置一致，检索与地理检查沿用原记录。

新增 `ActivitySceneBrowser`，由十五城预览和新版实际活动入口共用。照片全屏显示，场景通过原生分页手势和左右箭头切换。主操作为底部「去这里逛逛」胶囊按钮。已有进行中外出时显示「继续上次外出」，接回原有进度。

## 检查范围

| 范围 | 结果与证据 | 边界 |
| --- | --- | --- |
| G0–G2 原图与空间 | 沿用 v2，各场景照片与哈希一致 | 本版只改显示与交互 |
| G4/U1 全屏、裁切与单一入口 | 通过，iPhone 18 Pro 遍历十五城、54 处，逐张检查最终截图 | 本机 Debug，照片覆盖上下安全区 |
| G4/U1 手势、箭头和首尾边界 | 标准屏与 iPhone SE 3 均通过，左右手势及箭头更新同一标题、照片与按钮目标 | 首尾箭头停用，原生分页保留边缘阻尼 |
| G4/U1 小屏、大字号、许可与恢复 | 通过，SE 最大辅助字号覆盖长地点名、三处/五处末项、完整图及许可。实际阅读的开始、暂停、重启恢复与足迹通过 | 场景界面文字最大采用 accessibility2，阅读正文保留其既有字号设置 |
| G3 场景媒体 | 静态照片，沿用 v2 | 箭头使用原生 SF Symbols 呼吸提示，减少动态时停用 |

## 本版设计与验证边界

- 界面使用局部渐变保证浅色照片上的文字对比。地点名置于下方，顶部保留城市、返回与更多菜单。
- 照片来源、许可和完整图片收进更多菜单，实际活动入口同时保留足迹。主按钮与左右箭头沿用共享按压反馈，箭头命中区域 44×64pt。
- 全屏页内的照片同时忽略安全区，覆盖状态栏与底部手势条区域。
- 预览入口按选中地点显示「人物剧情正在接入」说明。实际活动入口通过原有 `onSelect` 开始该地点的外出，恢复按钮通过原有 `onResume` 接回记录。
- Computer Use 已显示 Device Hub 中的全屏界面，截图输出分辨率较低。坐标手势返回 `windowNotFoundAtPosition`，后续交互由定向 XCUITest 核验。
- 真机、人工 VoiceOver 连续使用及正式世界发布待完成。

## 最终证据

- `build/DerivedData/VerificationResults/20261114T060224Z-38390.xcresult`，标准屏 5 项通过，包含 54 场景加载遍历、手势与箭头目标一致、辅助字号与真实样板阅读流程。67 张截图保存在结果包。`build/ActivityWorldPhotos/fullscreen-v3/standard/sheet-1.jpg` 至 `sheet-4.jpg` 已逐表观察，四张关键原生截图保留在同目录，其余重复 PNG 导出已清理。
- `build/DerivedData/VerificationResults/20261114T061307Z-40438.xcresult`，iPhone SE 3、iOS 27.0，2 项通过。最大辅助字号下核对按钮可点、文字与侧箭头边界分离，包含内罗毕国家博物馆长标题。6 张原生截图在 `build/ActivityWorldPhotos/fullscreen-v3/compact/`，已查看长标题、两城末项、开场、全图与许可。
- 场景包校验、iOS 架构检查与 diff 检查通过。背景图片、哈希与许可清单无改动。
- 最早运行遇到模拟器 testmanagerd 连接失效，重启模拟器后恢复。第一次完整测试的 5 个用例均通过，结果打包因磁盘不足失败，原始通过日志保留在 `build/ActivityWorldPhotos/fullscreen-v3/standard-first-test-log.txt`。清理可再生的模拟器 Core ML 编译缓存后，重新运行得到上方完整结果包。小屏旧连接失效同样通过重新启动模拟器恢复。未删除数据库或账号资料。
- 被替代的 v2 标准屏结果包已清理，其测试摘要保留在 `build/ActivityWorldPhotos/fullscreen-v3/superseded-v2-summary.json`，v2 原截图浏览表仍可复用。v2 原图空间与许可结论继续沿用。
- 使用 `Scripts/preview.sh preview scenes-preview` 重新安装最新 Debug 产物，留在 iPhone 18 Pro。正式世界全量人物剧情仍待接入，生产内容保持原发布状态。
