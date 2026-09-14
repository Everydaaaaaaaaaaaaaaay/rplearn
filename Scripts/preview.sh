#!/usr/bin/env bash
# 复用当前 Debug 产物，以内存测试账号进入模拟器供交互检查。
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for candidate in /Volumes/data/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer; do
    if [[ -x "$candidate/usr/bin/xcodebuild" ]]; then
      export DEVELOPER_DIR="$candidate"
      break
    fi
  done
fi
if [[ -z "${DEVELOPER_DIR:-}" || ! -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]]; then
  echo "错误：请将 DEVELOPER_DIR 指向完整 Xcode 的 Contents/Developer。" >&2
  exit 1
fi

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/ios-worktree.sh"
cd "$LINGOTRIP_REPO_ROOT"

mode="${1:-preview}"
case "$mode" in
  help|--help|-h)
    echo "用法：Scripts/preview.sh [preview|build|status] [messages|contacts|home|map|me|subscription|learning]"
    echo "preview 复用 Debug 构建并免登录启动；build 先增量构建；status 只读设备与产物。"
    exit 0
    ;;
  preview|build|status) ;;
  *) echo "错误：不支持的命令：$mode" >&2; exit 1 ;;
esac
preview_tab="${2:-messages}"
case "$preview_tab" in
  messages|contacts|home|map|me|subscription|learning) ;;
  *) echo "错误：不支持的页面：$preview_tab" >&2; exit 1 ;;
esac
udid="$(lingotrip_simulator_udid)"
app_path="$LINGOTRIP_DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/LingoTrip.app"
if [[ "$mode" == status ]]; then
  echo "Xcode：$DEVELOPER_DIR"
  echo "设备：$udid"
  echo "产物：$app_path"
  xcrun simctl list devices booted
  exit 0
fi
lingotrip_acquire_pipeline_lock
if [[ "$mode" == build ]]; then
  lingotrip_prepare_workspace
  lingotrip_xcodebuild LingoTrip "$udid" -configuration Debug build
fi
if [[ ! -d "$app_path" ]]; then
  echo "错误：没有 Debug 产物，请先运行 Scripts/preview.sh build。" >&2
  exit 1
fi
bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$app_path/Info.plist")"
lingotrip_boot_simulator "$udid"
xcrun simctl install "$udid" "$app_path"
SIMCTL_CHILD_UI_TEST_SKIP_ONBOARDING=1 \
SIMCTL_CHILD_UI_TEST_REQUIRE_AUTHENTICATION=0 \
SIMCTL_CHILD_UI_TEST_DISABLE_BACKGROUND_REFRESH=1 \
SIMCTL_CHILD_UI_TEST_TAB="$preview_tab" \
SIMCTL_CHILD_LINGOTRIP_BACKEND_URL=http://127.0.0.1:9 \
  xcrun simctl launch --terminate-running-process "$udid" "$bundle_id"
echo "已安装并启动：${bundle_id}（${preview_tab}，本地 Debug 预览）"
echo "请在 Device Hub 选择设备 ${udid}，检查目标页面。"
