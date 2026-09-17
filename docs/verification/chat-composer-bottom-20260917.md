# 聊天输入栏底部缝隙 — 2026-09-17

## 现象

真机（iPhone，iOS 27）截图显示：输入栏下方还有一条约 35–50pt 的区域，能看到聊天内容，像输入栏
浮在屏幕底边之上。用户要求输入栏在**所有支持的系统版本和设备上都贴住屏幕最底部**，不接受用
材质把缝隙盖掉。

## 根因

输入栏是 `ChatView` 的 `safeAreaInset(edge: .bottom)`，消息列表在它下方依旧铺满整个视图。

- iOS 26：系统把底部安全区（home indicator）算进 `safeAreaInset` 视图自身，输入栏材质正好
  铺到屏幕底边；
- iOS 27：`safeAreaInset` 把输入栏放在安全区**上方**，输入栏只覆盖自己的内容高度，安全区里
  露出下面还在渲染的消息列表 → 那条"缝"。

已在 iOS 27.0 模拟器（iPhone 17 Pro，`3EBB1CAE-D66F-4CF5-AC18-C1C07F4DB7FB`）用
"联系人 → 发消息 → 聊天"的真实 push 路径复现；iOS 26.1 模拟器与 fullScreenCover 抓图路径
都不复现，与用户"iOS 27、一直存在"的描述一致。

## 修复

让输入栏自己拥有这段安全区，而不是靠覆盖：

- `ChatView` 用 `GeometryReader` 读取容器底部安全区并 `.ignoresSafeArea(.container, edges: .bottom)`；
- `inputBar(bottomInset:)` 把这段高度作为自己的底部内边距，**材质一起铺下去**（内容仍在
  home indicator 之上）；
- 软件键盘弹出时（`keyboardWillShow/Hide` 通知）不再补这段，输入栏直接贴在键盘上方。

结果：iOS 26 与 iOS 27 渲染一致——输入栏材质铺到屏幕底边、内容在 indicator 上方、消息列表
不会在输入栏下方露出；此前那版"补铺材质"的补丁已删除。

## 验证

- iOS 27.0 模拟器，聊天 push 后截图：输入栏材质到屏幕底边，无缝隙。
- iOS 27.0 模拟器，键盘弹出截图：输入栏直接位于键盘上方，没有多余材质带。
- iOS 26.1 模拟器（`47DD7BF7-5378-47D7-ACC3-792EF8AAFF11`）同一路径截图：与修复前一致，
  没有回归。
- `OnboardingWelcomeTests/testHandsOnTutorialUsesLocalTranslationDictionaryAndEncounter` 通过：
  教程里输入栏下方是教程自己的操作栏，外观无变化。

## 未完成

- 真机（iOS 27）复测仍需用户装包含本改动的构建后确认。
