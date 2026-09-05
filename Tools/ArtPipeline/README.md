# NPC 头像图库施工与验收

唯一生产图录：`Assets/NPC/Library/v3/catalog.json`。图录版本和 `styleVersion` 是不同概念；v3 使用 v5 美术规范。当前数量、真实测试结果见 `docs/npc-library/progress.md`。

## 角色卡与头像的顺序

1. 先生成叙事身份：年龄、性别、姓名、国籍、职业、性格、爱好、背景。外貌暂定，其他叙事字段不提前绑定发型、眼色、体型或衣着。
2. 后端用年龄区间、创作性别以及可选 `requiredAvatarTags` 硬约束，查询全部启用的已验收头像。不要把取前 N 张、最近生成一批或配色当作身份匹配。
3. 在该用户尚未见过的符合条件头像中均匀随机选择。`unknown` 体态不满足任何体态硬约束。国籍、职业与性格不从面相推断。
4. 同一事务保存 NPC、头像 ID 与关系。只用已审核图片描述填写 `appearance`；其他叙事字段保持原样。相同 NPC 的原始请求和最终角色卡重试都返回同一绑定。
5. 没有符合条件的图时返回 409，并记录 `coverage_gap`；有符合条件的图但用户已用完时记录 `user_pool_exhausted`。不换年龄、性别或叙事来迁就图库。补齐后可以原 ID 重试。

不同用户可重复使用同一幅画；同一用户的新随机 NPC 避开已有关联的头像，包括已移除关系。通过旅行者 ID 主动关联既有公共 NPC 属于同一公共身份，不重新随机生成头像。

iOS 目前在离线、游客或在线缺图时可以保留本地 NPC，头像待定；添加好友时再次注册。尚未实现后台自动重试。服务器图库发布与生产 CDN 验证是上线步骤，本次本地服务链测试不等于生产部署。

## 制作约束

- 内置 imagegen 每次生成一个独立头像，保留原图，将最终图复制进项目。禁止用换色或镜像增加身份计数。
- 主提示词在 `v3/style.txt`；每个条目的 `prompt` 保存完整实际提示词，`.receipt.json` 保存原始生成路径及生成时间。
- 明亮主题色 + 1–2 个深一层同色图形区域，约背景的 15–30%；可用弧面、斜切、宽侧带。无近黑底、纹理、渐变、杂色、字样。
- 一色系 + 近黑 + 中性白，面部、耳部和手部用少量形与线。人物比例、年龄与个人特征靠轮廓保留。
- 方形原图全出血，所有角落保留背景色。圆形由客户端裁切，原图不可预先加黑/白圆角遮罩。眼鼻嘴下巴和主要发形在圆内，无全身图。
- 先查看现有相似脸，再细化简报；不把高发髻、短刺发抬头、白额发、同位置痣作为默认模板。
- 生产词库含 60 面部、80 表情、80 发形、60 动作、15 镜头、60 服装组合。候选参数数目不等于已实现的视觉覆盖数。

## 逐图复核

```bash
node Tools/ArtPipeline/npc-library-audit.mjs audit /absolute/audit.json
python3 Tools/ArtPipeline/npc-similarity-audit.py \
  --catalog Assets/NPC/Library/v3/catalog.json --output /absolute/review
node Tools/ArtPipeline/npc-library-audit.mjs gallery /absolute/review.html
```

Python 需要 Pillow、NumPy。近邻方法比较归一化明暗与梯度，包含镜像；只是排序线索，不是人脸识别模型或身份唯一性的数学证明。

查看彩色圆形总览、64 px 缩略图、灰度前五近邻和可疑原图。实际脸型、表情、年龄范围、朝向、体态、服装逐图记录到 decisions JSON：

```json
[{"key":"npc-v5-001","ageMin":25,"ageMax":40,"facing":"left","expression":"calm","body":"unknown","appearance":"只描述实际可见的发型、脸部、衣着与动作。","notes":"列出最相似图和实际区别；圆裁与背景检查结论。"}]
```

`reject: true` 表示淘汰；审核工具检查图像 SHA 与近邻报告一致后写入 observed/review。必须实际看图，不可从 target 复制 observed 或按相似分数自动通过。

```bash
node Tools/ArtPipeline/npc-record-review.mjs /absolute/decisions.json /absolute/review/neighbors.json
```

淘汰图不计有效数量；删除项目中的淘汰副本前检查 SHA，保留原始生成出处和拒绝原因。背景回修沿用未发布身份 ID；已绑定资产不能原地修改，需新的资产 ID 与迁移方案。

## 真实批量测试 → 缺口 → 补图 → 复测

使用单独 PostgreSQL/Redis。测试要求 `app.npc_avatars` 为空，自动迁移并只清理本次夹具。不得指定生产数据库。

```bash
cd Backend
DATABASE_URL=postgres://test_user@127.0.0.1:55437/postgres \
REDIS_URL=redis://127.0.0.1:56387 \
RUN_NPC_LIBRARY_E2E=true \
NPC_REPORT_DIR=/absolute/round-100 \
NPC_E2E_SEEDS=90601,90602,90603 \
./node_modules/.bin/vitest run test/e2e/npc-library.test.ts \
  --maxWorkers=1 --no-file-parallelism
```

每种子默认 240 次、8 用户，年龄 14–85，三种创作性别；65% 请求带主题色，另含体态、朝向或表情硬约束。运行真实 HTTP 注册/邮件验证任务/登录/NPC 注册/原始及规范卡重试/公共查询，下载受信任本地 HTTPS PNG 并检查字节 SHA。叙事夹具是合成测试，未调用实时 LLM、原生 UI 或生产 CDN。

每成功一例写 checkpoint；整种子完成才写 `complete:true` 的正式报告。聚合工具拒绝不完整报告与不同图录哈希。每轮保留图录快照、逐例结果、缺口汇总；比较固定三种子，并加入新的留出种子检查泛化。生产选择仍用安全随机源，所以用户耗尽次数会略波动。

```bash
node Tools/ArtPipeline/npc-round-summary.mjs /absolute/summary.json
node Tools/ArtPipeline/npc-gap-report.mjs /absolute/round-100 /absolute/gaps-100.json
node Tools/ArtPipeline/npc-expand-plan.mjs 200 /absolute/gaps-100.json 20
```

超过 100 张的规划必须来自当前图录的真实完整测试报告，哈希过期直接拒绝。按缺口频率、严重度与同批分散惩罚安排；主题配额同时约束。规划仅写简报，不调用生图提供商。生成与人工视觉复核之后重新测试，再开始下一批，直到 200 张验收、五主题各 40 张。

将覆盖缺失、用户耗尽、候选深度不足分别报告。200 张不保证每种任意组合都有图，也不保证用户无限不重复；不得缩窄测试请求或放宽 observed 来伪造覆盖率。

## 发布门禁测试

```bash
node Tools/ArtPipeline/npc-library-gates.test.mjs /absolute/release-gates.json
```

在临时隔离图录中验证完整 200 张导出及 11 类拒绝条件：重复 ID、重复身份组、路径越界、过期 SHA、缺背景复核、缺图、重复像素文件、配色失衡、无效年龄、未复核候选、非 HTTPS。临时产物自动删除，不改实际图录。

## 导出与发布

```bash
node Tools/ArtPipeline/npc-library-audit.mjs export \
  /absolute/release/manifest.json https://YOUR-REAL-CDN/npc/
```

导出必须恰好达到当前 milestone、全部 SHA 绑定验收、五色配额完整、PNG 方形且不透明、没有重复字节、具有有效观察档案。输出 backend v2 manifest 和内容哈希命名 PNG。占位 CDN URL 仅用于本地检查，不可作为已发布结果。

上传 `release/images` 到实际对象存储并验证 HTTPS/SHA 后，以项目配置执行 `Backend` 的 `npc-avatars:import manifest.json`。导入整批原子提交，拒绝修改已绑定头像的 URL、画像档案、标签或状态。数据库迁移与真实 CDN 发布必须在部署环境执行；本地通过不声称已上线。
