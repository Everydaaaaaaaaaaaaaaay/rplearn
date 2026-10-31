# 城市地点与人物迁移内容源

`world.json` 是新版活动世界的内容源。目前为草稿，包含十五城、54 个候选地点，以及现有 200 人未经修改的身份和人物资料基线。地点组合在逐人适配审核后可以调整；草稿没有正式相遇绑定、照片或通过审核的故事，不能激活为生产发现池。

`sourceSHA256` 对应原始 `App/Resources/npc-library-v3.json` 的完整字节；每人的 `sourceCardHash` 使用递归按键排序、无多余空白的 JSON 与 SHA256。旧资料不作为生成时可被改写的草稿。新资料写在独立的 `assignment` 中，稳定身份和核心性格、价值观、职业、兴趣与边界由校验器保护。

人物适配需说明到场原因、对地点的态度、当下目标与状态，以及接触和反应的因果。讨厌某处可以因义务到场，健谈的人可以当时没有精力；不能用增加共同爱好或改性格来填满地点。照片、空间事实、人物与四条完整故事路径均经审核后才允许发布。

从 `Backend` 运行：

```sh
pnpm exec tsx src/cli/activity-world.ts validate ../Content/ActivityWorld/2026-10-31-places-v1/world.json ../App/Resources/npc-library-v3.json
pnpm exec tsx src/cli/activity-world.ts release-check ../Content/ActivityWorld/2026-10-31-places-v1/world.json ../App/Resources/npc-library-v3.json
```

第一条检查草稿结构、原身份和源文件；第二条还要求正式发布状态与完整的内容、照片、分配和验收证据。当前第二条应拒绝草稿。不得把自动结构校验通过记录成剧情或照片已获审核通过。
