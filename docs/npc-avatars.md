# NPC 文化头像

## 身份与范围

头像表达 NPC 会如何展示文化兴趣、审美和个性，不匹配年龄、性别、国籍或长相。
公开 NPC ID、旅伴号和基础角色卡仍跨用户一致；头像是按账号保存的身份投影。
同一 NPC 可以在两个用户那里使用不同头像。旅伴号查询现在需要认证，并且禁止共享缓存。

`user_npc_avatars` 独立于好友关系与内容墓碑：首次服务器展示前领取；注册重试、未加好友、
删除好友、清空聊天、再次搜索均保留绑定。用户注销并完成账号数据删除时按账号一并删除。
`(user_id, npc_id)` 和 `(user_id, family_id)` 的数据库约束分别保护幂等与不复用。
同源图片的裁切、调色、尺寸版本必须共享 familyId。固定剧情旅伴仍由现有本地主角流程管理；
如其图片入库，必须 reserved=true，不能参与随机分配。

旧版全局头像绑定在 0006 迁移中按历史关系（包括 removed）和创建者回填。旧图继续展示，
但缺少新版审核元数据的图不能再分配。迁移不会把原头像替换成文化图。

## 匹配第一版

`culture-map.ts` 是人工整理、带多语言别名的起始词表，不代表经过研究验证的全球文化地图。
从 hobbies 中识别明确文化兴趣，从 hobbies/personality 中识别审美与表达方式；
地区或国籍不会自动转成兴趣。图片 cultures/subjects 支持开放标签，可匹配词表外的新主题。
只有明确标记 interestIndependent=true 的通用审美图允许仅凭审美匹配，避免把安静误判成喜欢爵士乐。
先看所有可用库存，再进行文化关联、表达方式评分和轻度稀缺性惩罚；在高分候选中按账号与
NPC ID 做稳定随机选择。分配时保存偏好、命中项和算法版本，不把这些理由当作角色的个人经历。

这一版采用可解释的词表/标签匹配，**尚未接入向量检索或模型语义推理**，无法可靠理解隐喻、
否定句或全部兴趣同义表达。匹配不到时返回 NPC_AVATAR_UNAVAILABLE，不领取不相关图片。
既有 iOS 游客/离线偶遇仍显示姓名占位，联网后注册补领；占位不占图片库名额。
服务器成功分配的图片不会随个性成长重新匹配。客户端遇到加载失败只显示占位。

## 素材工作流

1. 从多语言文化资料发现题材，记录可核验的文化实体与关联。研究资料不是图片使用许可。
2. 结合文化地图与测试角色检查领域、地区、年代、社群、日常兴趣和表达方式的空缺。
3. 优先寻找许可适合的图片；原创生成适用于可原创表达的缺口，不自动解决人物、作品或品牌权利。
4. 审核来源、商业使用、改编和分发权限；署名和许可通知必须完整写入 attribution。
   选择允许在头像菜单提供署名的授权；如要求其他展示方式，在支持之前不得入库。
5. 检查文化准确性、适龄内容、小图效果和圆形裁切，并进行视觉相似度审核，分配 familyId。
6. 使用内容寻址的对象存储路径上传最终 PNG/JPEG/WebP。不要覆盖已发布 URL 的字节。
7. 写 version=2 清单，先 dry-run，再导入；最后运行覆盖审计，形成下一批素材任务。

现已提供可恢复的采集、授权条件初筛、SHA-256 去重、dHash 相似图提示、本地审核页、审核导出与 S3 兼容存储上传。
这些工具不会自动批准授权或文化标签；similarityChecked 等字段仍是审核声明。感知哈希只能提示部分近似图，
无法完整识别同一作品的不同角度、裁切或跨网站版本。后续批次必须使用累计候选库和累计审核记录，
与已发布图库一并核查 familyId，不能每批从零分家族。暂未实现批量生成任务。
AI 素材必须保留 model/prompt，并同样执行权利、文化和质量审核。

## 候选采集与来源

`Backend/npc-avatar-discovery.json` 是 54 个主题的首批检索计划，每主题默认收集 4 张不同字节的候选图。
这是检索配额，不是审核通过配额，也不代表全球文化覆盖。拒绝候选后应提高相应主题 target 或补充搜索，
不要删除旧记录或绑定来腾位置。`language` 记录查询语言；查询词本身决定多语言检索，不会自动翻译。

| 来源 | 补充方向 | 初筛条件与限制 |
| --- | --- | --- |
| Wikimedia Commons | 体育、音乐、生活、自然和跨地区文化 | 单图许可名称与标准 URL 必须一致；仅自动下载 CC0、CC BY 2.0/2.5/3.0/4.0 且未列限制的候选 |
| Cleveland Museum of Art | 器物、织物、书法、古典艺术 | 单件 `share_license_status=CC0`；不能把博物馆元数据开放当作全部图片开放 |
| Art Institute of Chicago | 版画、绘画、设计 | 单件 `is_public_domain=true`；当前环境图像端点返回 403，保留线索等待恢复 |
| Openverse（本轮检索 Flickr） | 当代生活、民间兴趣、体育、乐器、食物 | 搜索索引只提供线索；只下载白名单图片域名。批准时必须额外记录原作者页面的 `originalSourceCheck` |
| Metropolitan Museum of Art | 全球器物、棋具、服饰和版画 | 单件 `isPublicDomain=true` 且未附权利限制；审核时核对作品页的 CC0 标记 |

CC BY-SA 等不在当前自动下载清单的许可进入待核查，不等于不可使用。人物、商标、作品内嵌版权、
文化语境和小图效果均须另审；AI 也不能替代这些核查。Openverse 标签和博物馆搜索命中不能直接写入文化标签。
检索也保留失败和无结果，这些缺口应驱动扩展来源、调整查询和原创生成。

工作目录 `.avatar-workbench/` 已被 Git 忽略：`collection.json` 为可恢复检查点，`images/` 为原始下载字节，
`report.json` 为采集统计，`review.html` 提供原图、圆形与 40px 预览。采集报告的 approved 始终为 0，
正式审核数量和文化库存另见 `reviewed-report.json`。下载配额按尝试次数计，按主题轮换，失败重试让新候选先尝试。
搜索错误不推进游标；再次成功会清除错误。报告保留尚未成功重试的历史错误，即使主题已被其他来源补足。

同一目录禁止同时运行多个采集进程。异常退出留下 `.collection.lock` 时，先检查其中 PID 已退出，再删除过期锁。
不要一边采集一边编辑审核数据或发布。0 页 / 0 下载可仅校验本地文件并重建完整报告。

## 操作命令

在 Backend 目录使用 package.json 固定的 pnpm 10.11.0：

```bash
# 采集候选；需要系统 HTTP(S) 代理时，在 Node 24 中启用 NODE_USE_ENV_PROXY=1
NODE_USE_ENV_PROXY=1 pnpm npc-avatars:collect -- --pages 1 --downloads 120
# 按主题补图，仍保留完整计划和统计
NODE_USE_ENV_PROXY=1 pnpm npc-avatars:collect -- --topics weiqi,mahjong,books --pages 1 --downloads 24
# 只核验已审核文件，生成 reviewed-report.json 和 reviewed.html，不需要 CDN
pnpm npc-avatars:prepare -- --dir .avatar-workbench --review npc-avatar-pilot-review.json --review-only
# 指定实际 CDN 后，生成 prepared-manifest.json；此步不上载
pnpm npc-avatars:prepare -- --dir .avatar-workbench --review review.json --public-base https://YOUR-CDN/npc-avatars/
# 指定专用公开头像桶，才上传并生成 published-manifest.json
pnpm npc-avatars:prepare -- --dir .avatar-workbench --review review.json --public-base https://YOUR-CDN/npc-avatars/ --publish --bucket YOUR-AVATAR-BUCKET --prefix npc-avatars --region YOUR-REGION
pnpm npc-avatars:import -- npc-avatars.example.json --dry-run
pnpm npc-avatars:audit -- npc-avatars.example.json npc-avatar-personas.example.json
pnpm npc-avatars:import -- /absolute/path/reviewed-avatars.json
```

`npc-avatars.example.json` 仅示范格式，没有真实图片或许可，enabled=false，不能作为库存导入。
`npc-avatar-pilot-review.json` 是 8 张真实候选的 Codex 来源与视觉审核记录，另有 3 条不采用理由；
它不是发布清单，依赖对应本地检查点和 SHA-256 文件。审核者需填写真实来源、许可通知、展示裁切说明和 familyId。
Openverse 还需填写 `originalSourceCheck: {pageUrl, licenseUrl, evidence, checkedAt}`，核查原作者页后方可批准。
同字节不允许拆家族；dHash 接近但确实不同的作品需要 `distinctFrom` 明确记录。

采集退出码 2 表示有保留的搜索/下载错误，已成功成果和检查点仍可用；退出码 1 表示配置或运行错误。
上传使用 AWS SDK 默认凭据链；非 AWS 存储可加 `--endpoint https://YOUR-S3-ENDPOINT`。不要把密钥写入命令或清单。
工具不会改桶策略，也不会使用私有语音桶。CDN 基址必须与 bucket/prefix 的实际映射一致。
上传使用内容寻址键和条件写入，重试发现已有对象时校验字节，禁止覆盖。
部分上传失败不会输出新的发布清单；重跑可复用已验证对象，正式导入还会重新下载公开 URL 校验。

dry-run 只校验格式，
不证明图片合法。正式导入先下载最终 HTTPS 文件（不跟随跳转，15 秒超时，上限 5 MiB），
检查文件签名和 SHA-256，再原子写入数据库。一个清单失败不会部分入库。
同一 ID 的 URL、SHA-256 和 familyId 不可更改；审核元数据与启用状态可以更新。
数据库也阻止同字节哈希以不同 ID 重复入库。它不替代视觉相似度检查。

覆盖报告按 family 计数，报告文化库存、地区/年代/审美分布、表达多样性、候选不足、模拟连续偶遇耗尽、
只有审美命中和无法识别的兴趣。默认词表探针只能用于初筛；用多语言、交叉兴趣的真人式
角色测试集做验收。测试顺序会影响耗尽结果，重要类别应使用多种顺序重复模拟。

## 停用、撤图与容量

- enabled=false：暂停新分配，原 NPC 保留图片。
- withdrawn=true：API 不再返回图片，但永久绑定和去重名额保留。
- 下架还必须撤销对象存储/CDN访问和缓存；仅设置数据库标志不能撤回已下载的图片。
- 现有客户端缓存不会自动轮询撤图。紧急下架须在存储/CDN执行；版本化替换与主动客户端刷新待实现。
- 暂无自动修复/替换工具，禁止直接改 avatar ID 或删绑定来绕过。
- 固定库存存在每账号容量上限，也会局部先耗尽。审计发现缺口后补图，绝不回收历史名额。

## 上线门槛与后续阶段

本次交付是基础设施与验证工具，不包含 5,000 张真实图库，也不宣称文化覆盖已达标。
上线前需要完成首批许可审核素材、上传与正式导入，在独立环境演练迁移，并协调部署后端和
使用认证查询的新版客户端。旧版匿名旅伴号查询会收到认证失败；不可只升级服务器而忽略此兼容变化。

后续优先补充：有来源的文化知识地图、扩大真实素材审核与跨批次相似家族核查、按审核缺口自动补图与原创生成任务、
向量检索与偏好理解评估、线上匹配缺口统计、撤图替换和客户端刷新。

首批实际采集、审核和缺口见 [头像采集试运行报告](npc-avatar-pilot.md)。
