# 咕游记 · 2D 吉祥物动作资源包 V1

包含 8 张可直接导入的透明 PNG，以及通过独立 Xcode 资源编译的 `GuyujiMascots.xcassets`。
资源包已于 2026-09-08 通过 `project.yml` 接入 LingoTrip App target；不覆盖应用图标。

## 内容

| 角色 | 状态 | 资源名 | 建议场景 |
| --- | --- | --- | --- |
| 咕咕 | 开心招呼 | `mascot_gugu_welcome` | 欢迎、首次引导 |
| 咕咕 | 通关欢呼 | `mascot_gugu_celebrate` | 学习完成、成就 |
| 咕咕 | 好奇探路 | `mascot_gugu_explore` | 旅行、城市探索 |
| 咕咕 | 困困休息 | `mascot_gugu_rest` | 休息、安静等待 |
| 嘎嘎 | 鼓嘴小傲娇 | `mascot_gaga_pout` | 轻提醒、趣味反馈 |
| 嘎嘎 | 得意认可 | `mascot_gaga_proud` | 答对、达成目标 |
| 嘎嘎 | 害羞鼓励 | `mascot_gaga_care` | 鼓励、陪伴 |
| 嘎嘎 | 认真思考 | `mascot_gaga_think` | 提示、重试引导 |

## 使用

每张为 1254 × 1254 RGBA PNG，原生透明通道、无烘焙白底；8 张共 6,229,266 字节（约 5.94 MiB）。
图片位于各自 `.imageset` 内，未做裁剪、重采样或像素改色。
资源声明为 3x（418 pt 原生画布），保留完整分辨率；建议页面显示尺寸 100–300 pt。

整个 `GuyujiMascots.xcassets` 已在 `project.yml` 中声明为 LingoTrip 的资源目录，无需复制到 App 资源目录。
后续调整仍应修改 `project.yml`，而非只拖入生成的 Xcode 工程。
若置于 Swift Package 中，需声明 package resource，并使用其对应 Bundle。

导入 app target 后的示例：

```swift
Image("mascot_gugu_welcome")
    .renderingMode(.original)
    .resizable()
    .scaledToFit()
    .frame(width: 180, height: 180)
    .accessibilityHidden(true) // 仅当形象是装饰、状态已有可访问文本时
```

避免 `.scaledToFill()`、圆形裁切及模板着色；为头毛与动作留白。
不要预加载整套高清素材；页面仅使用当前需要的形象。

打开 `preview.html` 可查看浅色、深色、暖色、透明棋盘背景，并单独下载每张图片。
预览页支持直接本地打开；不依赖远程字体、脚本或网络服务。

## 形象与生成记录

使用内置 image_gen 工具，每个动作独立纯文字生成，共 8 次；无参考图输入、无图生图。
`manifest.json` 记录各图完整提示词、原始生成文件路径、资源名和用途。

角色基准仍是 `../duo-calibration-v1/corrected.png`。本套保留蓝/紫主色、各自脸部奶油色分区、翅膀斑点区别以及人设动作方向。
应明确：本套线条与阴影比定稿更浓，部分头毛增加了辅助尖羽，动作透视也带来比例差异；不是逐像素一致的母版延展。
“可导入”指透明格式与资源目录可用，不代表用户已确认全部造型差异，也不替换已确认的正面基准。

## 验证

`python3 Assets/Brand/Mascots/ui-pack-v1/verify.py`（依赖 Pillow，仅检查，不编辑图片）验证：

- 8 个独立且唯一的资源名；PNG 解码、尺寸和 RGBA 模式正确。
- 有完全透明、完全不透明和抗锯齿 Alpha 像素。
- 不透明主体未触及画布边界；极低透明度边缘可能触及边界，不据此宣称所有 Alpha 像素都有安全边距。
- 3x 资源条目与文件名一致；保存各图 SHA-256。

另已执行 `xcrun actool` 独立编译（iPhone/iPad、iphonesimulator、最低 17.0），退出码 0，无警告。
逐张查看输出，并在浏览器深色背景下检查了实际 UI 尺寸显示；修正了预览页 Grid 最小尺寸导致的裁图。
结果见 `verification.json`。正式接入后已完成 App 构建、聚焦映射测试及模拟器页面验收。
