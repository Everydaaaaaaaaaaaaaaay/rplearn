# 初高中多题型效果0.6

接续[0.5](ShowcaseDelivery-v0.5.md)，当前34完整组/234作答位。初一阅读下新增两个已有作者组：日历图文阅读、四图选项阅读。原32组228回应载荷相同，仍可在同年级/题型下切换完整组。

日历完整保留2027年4月、七列与全部日期/空格，不随系统时间变化；四图片候选原SVG按作者摘要绑定并内嵌，保留逐图英文替代描述。共有6新增展示回应/24候选，包括4图像选项；当前展示总逐题候选位置733（共享候选在不同响应重复呈现，不是733独立素材）。50参考形式空、37共享候选条目、9开放/写作响应及10输入框保持。

构建器校验完整日期格与四图资产，浏览器缺/坏/未加载图片时暂停提交及直接看参考。16准备控制＋11合成JS守卫控制通过，实际浏览器核验日历/四图加载、作答、状态隔离和参考展示。两组沿用原作者答案B/C/A和B/D/A，未经独立教研或学生标定，不把合成正确作答当独立金标。

入口仍为`http://127.0.0.1:8766/build/english-benchmark-showcase/index.html`，重建命令保持：

```sh
python3 -B Research/GuYouJi-English-Benchmark/Tools/build_school_showcase.py --output build/english-benchmark-showcase
```

见[选择0.6](showcase-selection-v0.6.json)、[标准0.53](PracticalAuthoringStandard-v0.53.md)及[研究记录](../Studies/2026-10-15-authored-calendar-and-four-image-choice-complete-display.md)。还有19作者组/104回应未显示；未新增源卷、作者或商用/学生/生产验证，不修改后端或iOS。
