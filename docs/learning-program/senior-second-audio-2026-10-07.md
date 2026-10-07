# 高中第二组离线音频记录

2026-10-07。全部20段由同源Supertonic3离线完整发言合成；双人录音采用F3/M5，两轮之间添加300毫秒数字静音，保留原有自然停顿。候选及最终增益母版分别经base.en、small.en无提示逐词核对。只做明确记录的大小写、标点、缩写、数字和同词正字法归一，不放宽否定、时态、同音词或额外词。

均为24kHz单声道PCM16，无削波；增益按目标RMS及峰值上限计算，无后期变速。以下表格由已验收媒体元数据复制，不生成任何教学文本。ASR和波形通过不代表独立人耳听感或教师效度验收。

| 年级 | 题号 | 秒 | 词/分 | 声线 | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| senior1 | s1.astra.a13 | 10.008 | 119.90 | F3 | `90de60b6746714fdd022a257256b40a499b16a8041044fdb3df30b8e763dc1d8` |
| senior1 | s1.astra.b15 | 10.921 | 120.86 | F3 | `e74f33eb1768a42abeadcc5be2821d74c32214077fb624235cc702ac80c27730` |
| senior1 | s1.astra.b02 | 8.443 | 120.81 | F3 | `f1f2c06d4a7d6db70ed76dbf6f2baccc3ee1f18adcd05496ca0c39924dd13597` |
| senior1 | s1.astra.b05 | 8.492 | 120.12 | F3 | `1fb793621add8392e4e3beb616dbfc76704979fed5cd6d8366e10b4d964287e2` |
| senior1 | s1.astra.b18 | 8.512 | 119.83 | F3 | `f0a3ff32a00ead1596ac36eabc89e326dc7dd4ee2b53bb535bd2286a7d28e3fd` |
| senior1 | s1.second.c16 | 17.004 | 116.45 | F3/M5 | `fa7644e2e5f2635436ea2b97f8f7a663e2538e57caa87a175db0b1adf41b7c11` |
| senior1 | s1.second.c18 | 5.736 | 115.07 | F3 | `46b6a78586ed4f65eb0a58583a85fd1c59c7e0374fdcaaa35cee8211297462e5` |
| senior2 | s2.astra.second.q13 | 2.999 | 120.03 | F3 | `a1597d3ffb228c0b70ec3feb01e61932939278b547dff4de4932f807abca6d36` |
| senior2 | s2.astra.second.q14 | 14.744 | 134.29 | F3 | `4f7786dd7c1a233898c26d7698f89ef632b884f5c765c2bac2c035671056849e` |
| senior2 | s2.astra.second.q15 | 14.591 | 131.59 | F3/M5 | `4226f38e8a779ab6521ef809fa43bf202627f92d07d4ffbd2cea8ec7c8696b91` |
| senior2 | s2.astra.second.q16 | 15.588 | 127.02 | F3 | `2455baceefe297c29581f8632b1f7bb5c4a64bb76a3aee65f5d55d436d18b4e6` |
| senior2 | s2.astra.second.q17 | 18.914 | 130.06 | F3/M5 | `f3060951035a31be7b040aa13ef3cde2f185703452cc0583f25743aa4aa0ded3` |
| senior2 | s2.astra.second.q18 | 19.042 | 132.34 | F3 | `fdf508e4c84cf386cf73e5f231b64837c09496731822793c5a19363ef0adb134` |
| senior3 | s3.second.q01 | 24.970 | 141.77 | F3/M5 | `c2802e0ea80255ed25e65b931e02843cb196f422c22e31b0ac5c91e3c1a62f97` |
| senior3 | s3.second.q03 | 3.739 | 128.37 | F3 | `2de6181fd76737ae3c680f8141d8318eeabb395d2a7c615f1795fde61a2244bd` |
| senior3 | s3.second.q04 | 19.239 | 140.34 | F3/M5 | `44f4bfad5cebca88f6068ba32d580fd2881ef9b0fd77166a215a1be62e0377ea` |
| senior3 | s3.second.q07 | 18.614 | 148.28 | F3 | `35c6aba1295505edc267f282e1c8d2f88ca5c55f086d680a46980f0d5cee6dc9` |
| senior3 | s3.second.q10 | 19.054 | 148.00 | F3/M5 | `7075e1d7098d07fdd604b5371236a3bd06484d4e578694a248ba89a19eecfdf8` |
| senior3 | s3.second.q12 | 4.893 | 134.90 | M5 | `a8443befd2092d4ef0e654ca87952d186f68b33ffc0f7d84dc86a6d90853d28b` |
| senior3 | s3.second.q14 | 23.499 | 148.09 | F3 | `db89447808f0ed9fc06e926fc05876d5cc9b1c7b30b71abf63c2d8aba180299f` |

高三q01经历明确的文字返修，仍保持B的立场转向及房间尚待确认。新末轮仅两候选；take20完整母版出现额外词而淘汰，take21完整母版严格通过。旧三个失败母版与新失败母版均保留，未删除额外词或裁尾来满足校验；其余六段母版哈希不变。文字依据见[逐题终审](senior-second-review-2026-10-07.md)。

逐发言声线、SDK速率、所选take、逐采样静音与增益比对，以及原始识别日志，保存在`build/learning-expansion-20261007/senior-audio/<level>/`。这些短录音是局部能力练习，不代表完整高中听力考试或全年课程覆盖。
