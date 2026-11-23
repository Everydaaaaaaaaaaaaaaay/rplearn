# 城市地点与人物迁移内容源

`world.json` 是新版活动世界的内容源。本版草稿包含十五城、54 个当地实拍地点、200 人的唯一地点绑定、200 篇七节点初遇与 200 段重逢，共 800 条可游玩初遇路径。每处绑定 3–4 人。完整人物和原始资料基线保留，人物与故事状态分别为 pending 和 draft。2026-11-15 已汇总审校批准并编译正式发布包，详见末节。源文件继续保留草稿状态，发布包独立存储。

`sourceSHA256` 对应原始 `App/Resources/npc-library-v3.json` 的完整字节；每人的 `sourceCardHash` 使用递归按键排序、无多余空白的 JSON 与 SHA256。旧资料不作为生成时可被改写的草稿。新资料写在独立的 `assignment` 中，稳定身份和核心性格、价值观、职业、兴趣与边界由校验器保护。

人物适配需说明到场原因、对地点的态度、当下目标与状态，以及接触和反应的因果。讨厌某处可以因义务到场，健谈的人可以当时没有精力；不能用增加共同爱好或改性格来填满地点。照片、空间事实、人物与四条完整故事路径均经审核后才允许发布。

`assignments.json` 固定 200 人的城市、唯一地点、真实国籍代码、成长地和在地关系。`geography-decisions.json` 逐项记录 16 人的现居城市调整，以及 Marisol Vega、Simon Holt、Achieng Opondo 和 Baraka Kimani 的四项地理澄清。旧卡中的九处虚构国籍和八处虚构家乡已有明确纠错说明。Declan 的家乡字段另清理一处旧现居描述，保留 Drogheda 家乡与都柏林生活史。180 人沿用传记原文，20 人因迁城、地理澄清或旧场景表述修订传记。

国籍代码使用 ISO 3166-1 alpha-2，标签与成长地必须和新角色卡一致；不能用虚构国家补位。正式发布要求每城长期在地生活角色超过一半，包括本地成长和长期定居。两种经历分别记录，短期停留另列；既有迁居经历不为配额改写。跨城流动和编辑纠错仍需逐人给出事实依据与修订说明。

从 `Backend` 运行以下检查。

```sh
pnpm exec tsx src/cli/activity-world.ts validate ../Content/ActivityWorld/2026-10-31-places-v1/world.json ../App/Resources/npc-library-v3.json
pnpm exec tsx src/cli/activity-world.ts release-check ../Content/ActivityWorld/2026-10-31-places-v1/world.json ../App/Resources/npc-library-v3.json
```

第一条检查草稿结构、原身份和源文件；第二条还要求正式发布状态与完整的内容、照片、分配和验收证据。当前第二条应拒绝草稿。不得把自动结构校验通过记录成剧情或照片已获审核通过。

## 2026-11-14 剧情审校记录

人物分配、到场理由、地点态度、当天状态、接触与四路结果见 [roster.md](roster.md)。逐人结果、误报裁决、城市审校建议、最终正文指纹及费用口径见 [editorial-review-20261114.json](editorial-review-20261114.json)。

创作与横向审校使用独立 OpenAI key。200 人完成逐人全路径复核，随后对 75 人复核修订稿。十五城完成两轮完整横向审校，两轮定向 patch 分别覆盖 174 人与 71 人。每次保留无需修订的节点，减少相同掉物、让座、措辞误会和小失误重逢的集中出现。

最终模型意见为 197 人 pass、3 人 revise。三项 revise 均经上下文裁决，涉及已出版信件的收信人、向第三人的直接称呼，以及重逢另一天的个人安排。对应文本补清称呼与叙述，原卡代词和人物关系保持一致。模型结果和本轮人工裁决继续作为草稿证据，正式发布批准单独记录。

照片沿用 CityPlaces-v2 的同城实拍与既有验收证据，本轮未改图片。独处仍为三个地点六段，其余地点需要在世界发布前补齐。线上未导入本版内容，旧联系人迁移仍待接入。

私有流水按请求键与请求哈希合并去重，含弃用稿、失败尝试与未知请求预留。按 token 用量和公开价格上限估算约人民币 211.61 元，其中未知费用请求预留约 5.70 元。按 USD/CNY 7.2 换算，具体账单以供应商记录为准。初期线上 OpenRouter key 触及累计上限后，用户已调至 15 美元，最小调用确认恢复。后续创作使用独立 OpenAI key，本机临时密钥文件已删除。

## 2026-11-14 当前 GPT 会话审校

本轮在当前 GPT 会话中直接通读、改写并横向比较。外部模型 API 调用为零。逐人绑定结论、四路覆盖、修订原因和最终正文指纹见 [editorial-account-review-20261114.json](editorial-account-review-20261114.json)。上节及其记录对应此前的 API 流程。

覆盖十五城、54 地点、200 人的全部初遇节点和选择、800 条初遇路径及 200 段重逢。通读以英文正文为主，修订内容完成中英对照复核，其他译文沿用。最终有 62 人的正文发生变化，包含 34 篇初遇、89 个初遇节点和 37 段重逢。

200 个既有地点绑定均有成立的到场理由，本轮沿用分配，通过义务、等候、私人兴趣、工作后的休息及同伴安排细化当日情境。重点修订旧食谱谜题、颜色和措辞评判、录音隐私、风筝布和包带、同场景采购，以及重逢复演初遇或统一收起爱好的桥段。人物可保留不快、固执和未解决的处境，重逢信息由当次情境重新交代。

正文修正同时覆盖未选择的玩家回答、物件持有状态、跨分支才发生的交付和错误的“再次”表述。共享编辑投影仅在历史回访前缀中清理地点指代，保留真实的同岸、同层空间关系，并加入回归测试。

本轮通过草稿 CLI 校验、7 项内容单元测试与 10 项内容流水线测试。与修订前快照核对身份、头像、城市地点、资料卡、路径图和配额，逐人指纹及检查结果收录于本轮记录。当前发布阶段仍为草稿，正式发布、活动入口及旧联系人迁移待后续集成。

## 2026-11-15 高清照片与剧情绑定复核

本轮同步 54 张高清实拍及其媒体指纹。皇家港查尔斯堡替换德文大宅庭院，四位角色的草稿地点、到场安排、庭院空间与双语叙述随之修订。解放公园改用蓝马霍树，三位角色的拍摄对象、树影和停留位置同步调整。

其他修订覆盖滨海湾螺旋桥北端的岸侧、维多利亚女王市场的棚号、圣劳伦斯市场的钟形挂饰，以及卡斯尔菲尔德铁路桥铁栏和无护栏纤道的区别。共 21 篇故事修订，逐篇原因、前后指纹与保护检查见[照片绑定复核](photo-binding-review-20261115.json)。本轮直接使用当前 GPT 会话，外部模型 API 调用为零。

已核对 200 人身份、原卡、新资料卡、头像、城市、故事 ID 与路径图。照片来源和本版视觉验收见[高清记录](../../../Assets/Activities/CityPlaces-v2/acceptance-v7.md)。本版继续处于草稿阶段，正式世界发布与联系人迁移仍待后续集成。

## 2026-11-15 正式发布编译与原生接入

200 篇当前正文均匹配逐人审校和照片空间复核中的最终指纹。发布批准记录逐篇、逐图指纹。每处独处改为同一句中英文提示，共 54 份稳定地点 ID，阅读页只显示正文与正常结束入口。[发布审校单](release-review-20261115.json)

正式包位于 `Backend/config/activity-world/2026-10-31-places-v1.json`，App 配套清单为 `App/Resources/activity-world-release.json`。发布编译器验证批准单与精确草稿哈希、全部故事指纹及 54 个实际照片文件，随后生成批准状态的不可变世界和原生资料迁移清单。App 清单同时包含隔离离线预览所需的相同正文，`Scripts/preview.sh preview world-preview` 可在模拟器游玩，`UI_TEST_SCENE_CITY` 可指定城市。

联系人迁移在账号内容载入后执行，更新现居、国籍、家乡及必要背景，并保存原资料和解释。资料页可展开查看历史，后续聊天使用当前设定。同步端保留已有版本与历史，并兼容旧设备提交的资料。游客认领先重放本机队列，合并各城足迹，并保存可查看的冲突前副本。双外出由用户选择继续哪次，另一次结束后写入足迹。服务器历史补齐其他设备上的结束记录。

本地验证包含 30 项原生测试、12 项隔离数据库测试、实际生产代码组合的 9 项隔离兼容测试，以及照片清单与发布 CLI 检查。全量内容测试真实预定了 200 人，检查 54 地点重逢，并运行 800 条纯状态路径。线上发布证据与真机显示状态以最新施工进度记录为准。本轮外部模型 API 调用为零。

正式世界已启用，后端发布版本为 `activity-world-20261115-v1-91e6583b`。线上相遇、认领与资料同步验证通过。[发布证据](../../../docs/verification/activity-world-release-20261115.json)

重新编译使用以下命令，内容批准绑定精确草稿和素材字节。

```sh
pnpm exec tsx src/cli/compile-activity-world.ts ../Content/ActivityWorld/2026-10-31-places-v1/world.json ../Content/ActivityWorld/2026-10-31-places-v1/release-review-20261115.json ../App/Resources/ActivityPlacesGallery config/activity-world/2026-10-31-places-v1.json ../App/Resources/activity-world-release.json
pnpm exec tsx src/cli/activity-world.ts release-check config/activity-world/2026-10-31-places-v1.json ../App/Resources/npc-library-v3.json
```

## 2026-11-22 相遇故事重写

[本轮修订源](encounter-rewrites-20261122.json)覆盖 28 处地点的 101 位角色。每人重写中英双语初遇、四条路线与重逢，按角色卡、地点事实及同地点题材复核。伦敦、纽约、新加坡、悉尼、墨尔本、奥克兰及开普敦波卡普共 99 篇沿用基版正文。角色卡、地点、头像、独处文案和照片沿用基版。

从 `Backend` 编译 [本轮审校版](release-review-20261122.json)到后端与 App。这次仍使用角色资料版本 1。安装新版 App 后，新外出选择新版内容。旧版目录继续可读，已开始的外出和足迹从各自的剧情快照恢复。

```sh
source_dir=../Content/ActivityWorld/2026-10-31-places-v1
pnpm exec tsx src/cli/compile-activity-world.ts "$source_dir/world.json" "$source_dir/release-review-20261122.json" ../App/Resources/ActivityPlacesGallery config/activity-world/2026-11-22-encounters-v2.json ../App/Resources/activity-world-release.json "$source_dir/encounter-rewrites-20261122.json"
pnpm exec tsx src/cli/activity-world.ts release-check config/activity-world/2026-11-22-encounters-v2.json ../App/Resources/npc-library-v3.json
```

整包发布时，数据库迁移入口在既有世界已启用的前提下登记新版。首次初始化数据库仍需按既有流程导入身份库和基版，再登记新版。

## 中文口语修订

[中文修订源](encounter-chinese-review-20261122.json)沿用上面的 101 位角色，复审中文旁白、台词、选项和重逢。英文、故事节点、地点与角色绑定沿用 v2。后端登记 v3 后，已经启用的 v1 与 v2 继续服务旧客户端和既有外出。

从 `Backend` 生成当前发布包。

```sh
source_dir=../Content/ActivityWorld/2026-10-31-places-v1
pnpm exec tsx src/cli/compile-activity-world.ts "$source_dir/world.json" "$source_dir/release-review-20261122-zh.json" ../App/Resources/ActivityPlacesGallery config/activity-world/2026-11-22-encounters-v3.json ../App/Resources/activity-world-release.json "$source_dir/encounter-chinese-review-20261122.json"
pnpm exec tsx src/cli/activity-world.ts release-check config/activity-world/2026-11-22-encounters-v3.json ../App/Resources/npc-library-v3.json
```

## 网页版 AI 改写资料

[创作说明与交稿接口](authoring/README.md) 对应当前城市相遇运行规则。在仓库根目录运行以下命令，可从发布包导出角色总表、逐城完整角色卡、地点事实和独立的 JSON 交稿模板。

```sh
node Tools/ContentPipeline/export-encounter-authoring.mjs
```

输出位于 `build/encounter-authoring`。导出器逐人比对后端发布包和 App 随包资料。
