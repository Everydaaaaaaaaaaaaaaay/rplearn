#!/usr/bin/env bash
# 安装当前 Debug 产物，进入预览或连接本机隔离后端。
set -euo pipefail

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for candidate in /Volumes/data/Applications/Xcode.app/Contents/Developer /Applications/Xcode.app/Contents/Developer /Applications/Xcode-beta.app/Contents/Developer; do
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
    echo "用法：Scripts/preview.sh [preview|build|status] [messages|contacts|home|map|me|settings|subscription|learning|learning-test|role-learning|unit-challenge|practice-preview|achievement-preview|promotion-preview|places-preview|world-preview|scenes-preview|appointments-preview|mascots-preview]"
    echo "preview 复用 Debug 构建并免登录启动；build 先增量构建；status 只读设备与产物。"
    echo "LINGOTRIP_SIMULATOR_BACKEND_URL=http://127.0.0.1:<端口> Scripts/preview.sh connected  安装当前构建并进入正常登录流程。"
    exit 0
    ;;
  preview|build|status|connected) ;;
  *) echo "错误：不支持的命令：$mode" >&2; exit 1 ;;
esac
if [[ "$mode" == connected ]]; then
  backend_url="${LINGOTRIP_SIMULATOR_BACKEND_URL:-}"
  if [[ ! "$backend_url" =~ ^http://127\.0\.0\.1:[0-9]{1,5}$ ]]; then
    echo "错误：LINGOTRIP_SIMULATOR_BACKEND_URL 需要指定本机隔离后端的地址与端口。" >&2
    exit 1
  fi
  curl --fail --silent --show-error --max-time 5 "$backend_url/health/ready" >/dev/null
fi
preview_tab="${2:-messages}"
case "$preview_tab" in
  messages|contacts|home|map|me|settings|subscription|learning|learning-test|role-learning|unit-challenge|practice-preview|achievement-preview|promotion-preview|places-preview|world-preview|scenes-preview|appointments-preview|mascots-preview) ;;
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
lingotrip_purge_model_cache "$udid" "$bundle_id"
xcrun simctl install "$udid" "$app_path"
if [[ "$mode" == connected ]]; then
  SIMCTL_CHILD_LINGOTRIP_BACKEND_URL="$backend_url" \
    xcrun simctl launch --terminate-running-process "$udid" "$bundle_id"
  echo "已连接本机隔离后端。请在 Device Hub 选择设备 ${udid}。"
  exit 0
fi
if [[ "$preview_tab" == learning-test ]]; then
  SIMCTL_CHILD_UI_TEST_REQUIRE_AUTHENTICATION=1 \
  SIMCTL_CHILD_UI_TEST_SKIP_ONBOARDING=1 \
  SIMCTL_CHILD_UI_TEST_DISABLE_BACKGROUND_REFRESH=0 \
  SIMCTL_CHILD_UI_TEST_TAB=learning-test \
  SIMCTL_CHILD_LINGOTRIP_BACKEND_URL="${LINGOTRIP_TRIAL_BACKEND_URL:-https://rplearn.haruyuki.cn}" \
    xcrun simctl launch --terminate-running-process "$udid" "$bundle_id"
  echo "已启动真实学习实测入口；需要真实登录，答题使用服务端题库与计分。"
  exit 0
fi
SIMCTL_CHILD_UI_TEST_SKIP_ONBOARDING=1 \
SIMCTL_CHILD_UI_TEST_REQUIRE_AUTHENTICATION=0 \
SIMCTL_CHILD_UI_TEST_DISABLE_BACKGROUND_REFRESH=1 \
SIMCTL_CHILD_UI_TEST_TAB="$preview_tab" \
SIMCTL_CHILD_LINGOTRIP_BACKEND_URL=http://127.0.0.1:9 \
  xcrun simctl launch --terminate-running-process "$udid" "$bundle_id"
echo "已安装并启动：${bundle_id}（${preview_tab}，本地 Debug 预览）"
echo "请在 Device Hub 选择设备 ${udid}，检查目标页面。"
