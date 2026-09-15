# 咕游记 · 把英语，聊成生活

44秒原生产品宣传片，1080×1920 / 60fps，Remotion 4.0.524。

## 观看与编辑

交付目录：`/Users/tiantian/Movies/Coovingo-Promo-20260915/`。

```sh
cd Tools/coovingo-film
npm ci
# 只有从 Git checkout、缺少 public/media 时才需要恢复素材：
python3 scripts/prepare.py
npm run dev -- --no-open --port=3127
npm run render
```

当前预览：http://localhost:3127/Coovingo 。可移植工程ZIP已包含 public/media，解压后无需执行 prepare.py。Git不提交渲染文件、派生媒体和node_modules；原素材哈希见 assets.json。macOS使用系统 PingFang SC；其他平台应安装对应中文字体以保持版式。

## 结构

- `RESEARCH.md`：产品深入梳理、来源、成熟度与分镜取舍。
- `src/scenes/`：七个可编辑场景。
- `src/design.tsx`：版式、原生像素裁切与逐帧动效。
- `src/Film.tsx`：时间线与配乐。
- `scripts/capture-motion.py`：隔离Debug原生录屏/实机截图。
- `scripts/prepare.py`：媒体恢复、音频剪辑与正常速度转码。
- `CREDITS.md`：配乐与图像来源。片尾也包含音乐署名。
- `QA.md`：验证与拍摄范围。

## 拍摄

已安装具有本任务Debug拍摄开关的构建。只在固定内存账号启用，不修改真实账号数据。手机不支持CoreDevice远程录屏时，使用 `--screenshots-only`；动态录屏使用 `--simulator`。不要用截图帧拼装假冒原生录屏。

```sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
python3 scripts/capture-motion.py --device 00008110-00092C493C0B801E \
  --screenshots-only --output /Users/tiantian/Movies/Coovingo-Promo-20260915/raw

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
python3 scripts/capture-motion.py --device 47DD7BF7-5378-47D7-ACC3-792EF8AAFF11 \
  --simulator --output /Users/tiantian/Movies/Coovingo-Promo-20260915/raw/take2
```

重新录制会得到新的时间/画面哈希，必须复查后更新清单。原版raw/take2保留，不应覆盖；上方命令仅用于理解当次调用，重拍请换新的目录。
