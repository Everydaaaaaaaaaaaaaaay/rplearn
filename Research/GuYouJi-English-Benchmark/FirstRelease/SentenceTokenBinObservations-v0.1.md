# 现行句单位token分布观察0.1

[结构化记录](sentence-token-bin-observations-v0.1.json)取卡0.4已明示句界的12源/10当前作者；开放读答1源/1作者未标句界，保留unknown，不能补零或猜分句。所选源/当前稿去重，历史初稿不加为当前样本。

| 年级/实例 | 句数 | 1—10 | 11—20 | 21—30 | 31—40 | 41以上 | 最长 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 7 / g7.2021.readingB (source) | 24 | 17 | 7 | 0 | 0 | 0 | 17 |
| 7 / grade7-library-v0.1 (authored_current) | 20 | 13 | 7 | 0 | 0 | 0 | 17 |
| 8 / g8.2025.readingC (source) | 27 | 6 | 17 | 3 | 1 | 0 | 31 |
| 8 / grade8-lunch-v0.1 (authored_current) | 20 | 8 | 11 | 1 | 0 | 0 | 22 |
| 8 / g8.2025fengtai.readingB (source) | 21 | 3 | 16 | 2 | 0 | 0 | 24 |
| 8 / grade8-music-afternoon-reading-v0.1 (authored_current) | 23 | 4 | 17 | 2 | 0 | 0 | 21 |
| 8 / g8.changjun2024.readingC (source) | 18 | 4 | 12 | 1 | 1 | 0 | 37 |
| 8 / grade8-wayfinding-exhibition-reading (authored_current) | 17 | 3 | 14 | 0 | 0 | 0 | 18 |
| 9 / g9.2026.readingC (source) | 24 | 10 | 12 | 2 | 0 | 0 | 25 |
| 9 / grade9-book-repair-v0.1 (authored_current) | 22 | 8 | 11 | 3 | 0 | 0 | 22 |
| 10 / g10.2024.readingD (source) | 13 | 0 | 3 | 5 | 5 | 0 | 37 |
| 10 / grade10-roof-reading-v0.2 (authored_current) | 12 | 0 | 3 | 7 | 2 | 0 | 35 |
| 11 / g11.2025.readingD (source) | 17 | 2 | 8 | 3 | 4 | 0 | 40 |
| 11 / grade11-commitments-reading-v0.2 (authored_current) | 15 | 0 | 5 | 8 | 2 | 0 | 34 |
| 12 / g12.2025anshan.readingC (source) | 18 | 0 | 10 | 8 | 0 | 0 | 30 |
| 12 / grade12-dashboard-reading-v0.1 (authored_current) | 23 | 6 | 13 | 4 | 0 | 0 | 29 |
| 10 / g10.wenzhou2025.readingD (source) | 16 | 2 | 11 | 3 | 0 | 0 | 29 |
| 10 / grade10-library-booking-screen-reading (authored_current) | 20 | 5 | 13 | 2 | 0 | 0 | 21 |
| 12 / g12.national2025.readingD (source) | 15 | 2 | 6 | 4 | 3 | 0 | 38 |
| 12 / grade12-parcel-label-trial-reading (authored_current) | 22 | 2 | 13 | 7 | 0 | 0 | 27 |
| 7 / g7.xicheng2025.readingB (source) | 30 | 18 | 11 | 0 | 1 | 0 | 31 |
| 11 / g11.spring2024.readingD (source) | 15 | 0 | 11 | 2 | 2 | 0 | 36 |

分箱为固定展示口径，不是经验标定的“长句”分界，也不是从句比例/嵌套深度。数字由冻结显式句单位复算，不会校正作者分句本身的语言学争议。均值/中位/最长是单位长度，词汇义项、非限定结构、指代、问题操作、选项长度/支架仍分开审核。

初一新叙事源最长31，高三既有论证源最长30；这种跨年级重叠说明不能把最大句长当年级排序器。两份原卷都只是选定样本，不由此说所有初一比高三复杂。高一功能源最长29却按声明口径单句可有6有限单位，见[逐句标注](Expansions/Grade10FunctionFiniteUnitControls-v0.1.md)；单看token桶不能替代结构。

高三新稿初测21单位/max39在31—40桶产生一条，显式核对引号后的下一句后变22单位/max27、该桶清零。正文364词不变，旧profile和错误路径保留。不能把这个测量伪长单位当新出现复杂句、迭代成果或学生负荷增加。

本表不能直接成为入口模型的年级上限/百分比规范。生成者按完整锚的操作/语言关系选参照，再提交自己的分组件输入及偏离理由；没有独立学生资料时，只描述这组材料而不输出CEFR/分钟/升星结论。41原创/271响应、101源实例/639参考/18父身份、28源/17核心和14请求均不因本表增加，全部长期门槛保留。
