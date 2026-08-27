#!/usr/bin/env bash

# 多工作树共用的 iOS 构建基础设施。
# 调用方应先启用 `set -euo pipefail`，再 source 本文件。

LINGOTRIP_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINGOTRIP_GIT_COMMON_DIR="$(git -C "$LINGOTRIP_REPO_ROOT" rev-parse --path-format=absolute --git-common-dir)"
LINGOTRIP_MAIN_REPO_ROOT="$(dirname "$LINGOTRIP_GIT_COMMON_DIR")"
LINGOTRIP_SHARED_BUILD_ROOT="${LINGOTRIP_SHARED_BUILD_ROOT:-$LINGOTRIP_MAIN_REPO_ROOT/build/WorktreeShared}"
LINGOTRIP_DERIVED_DATA_PATH="${LINGOTRIP_DERIVED_DATA_PATH:-$LINGOTRIP_REPO_ROOT/build/DerivedData}"
LINGOTRIP_SOURCE_PACKAGES_PATH="${LINGOTRIP_SOURCE_PACKAGES_PATH:-$LINGOTRIP_SHARED_BUILD_ROOT/SourcePackages}"
LINGOTRIP_PIPELINE_LOCK_DIR="$LINGOTRIP_SHARED_BUILD_ROOT/locks/ios-pipeline.lock"
LINGOTRIP_PIPELINE_LOCK_HELD=0

lingotrip_require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "错误：缺少命令 $command_name" >&2
    exit 1
  fi
}

lingotrip_remove_stale_lock() {
  local stale_lock="$LINGOTRIP_PIPELINE_LOCK_DIR.stale.$$"
  if mv "$LINGOTRIP_PIPELINE_LOCK_DIR" "$stale_lock" 2>/dev/null; then
    rm -f "$stale_lock/pid" "$stale_lock/worktree" "$stale_lock/started_at"
    rmdir "$stale_lock" 2>/dev/null || true
  fi
}

lingotrip_release_pipeline_lock() {
  if [[ "$LINGOTRIP_PIPELINE_LOCK_HELD" != "1" ]]; then
    return
  fi

  local owner_pid=""
  if [[ -f "$LINGOTRIP_PIPELINE_LOCK_DIR/pid" ]]; then
    owner_pid="$(<"$LINGOTRIP_PIPELINE_LOCK_DIR/pid")"
  fi

  if [[ "$owner_pid" == "$$" ]]; then
    rm -f \
      "$LINGOTRIP_PIPELINE_LOCK_DIR/pid" \
      "$LINGOTRIP_PIPELINE_LOCK_DIR/worktree" \
      "$LINGOTRIP_PIPELINE_LOCK_DIR/started_at"
    rmdir "$LINGOTRIP_PIPELINE_LOCK_DIR" 2>/dev/null || true
  fi
  LINGOTRIP_PIPELINE_LOCK_HELD=0
}

lingotrip_acquire_pipeline_lock() {
  mkdir -p "$LINGOTRIP_SHARED_BUILD_ROOT/locks" "$LINGOTRIP_SOURCE_PACKAGES_PATH"

  local waited_seconds=0
  while ! mkdir "$LINGOTRIP_PIPELINE_LOCK_DIR" 2>/dev/null; do
    local owner_pid=""
    local owner_worktree="未知工作树"
    if [[ -f "$LINGOTRIP_PIPELINE_LOCK_DIR/pid" ]]; then
      owner_pid="$(<"$LINGOTRIP_PIPELINE_LOCK_DIR/pid")"
    fi
    if [[ -f "$LINGOTRIP_PIPELINE_LOCK_DIR/worktree" ]]; then
      owner_worktree="$(<"$LINGOTRIP_PIPELINE_LOCK_DIR/worktree")"
    fi

    if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
      echo "发现已失效的 iOS 流水线锁，正在恢复"
      lingotrip_remove_stale_lock
      continue
    fi

    # mkdir 与写入 PID 之间存在极短窗口；只在空锁超过 30 秒后清理。
    if [[ -z "$owner_pid" ]]; then
      local now modified_at
      now="$(date +%s)"
      modified_at="$(stat -f %m "$LINGOTRIP_PIPELINE_LOCK_DIR" 2>/dev/null || echo "$now")"
      if (( now - modified_at > 30 )); then
        echo "发现未完成初始化的 iOS 流水线锁，正在恢复"
        lingotrip_remove_stale_lock
        continue
      fi
    fi

    if (( waited_seconds % 16 == 0 )); then
      echo "另一工作树正在构建或操作模拟器，当前任务排队中：$owner_worktree"
    fi
    sleep 2
    waited_seconds=$((waited_seconds + 2))
  done

  printf '%s\n' "$$" > "$LINGOTRIP_PIPELINE_LOCK_DIR/pid"
  printf '%s\n' "$LINGOTRIP_REPO_ROOT" > "$LINGOTRIP_PIPELINE_LOCK_DIR/worktree"
  date -u '+%Y-%m-%dT%H:%M:%SZ' > "$LINGOTRIP_PIPELINE_LOCK_DIR/started_at"
  LINGOTRIP_PIPELINE_LOCK_HELD=1
  trap lingotrip_release_pipeline_lock EXIT
}

lingotrip_prepare_workspace() {
  local voice_models="${1:-required}"
  lingotrip_require_command xcodegen
  lingotrip_require_command xcrun

  cd "$LINGOTRIP_REPO_ROOT"
  mkdir -p "$LINGOTRIP_DERIVED_DATA_PATH" "$LINGOTRIP_SOURCE_PACKAGES_PATH"
  if [[ "$voice_models" != "skip" ]]; then
    local voice_model_stamp="$LINGOTRIP_DERIVED_DATA_PATH/VoiceModelVerification/bundled-voice-models.verified"

    if ! Scripts/verify-bundled-voice-models.sh "$voice_model_stamp" >/dev/null 2>&1; then
      lingotrip_require_command git
      if ! git lfs version >/dev/null 2>&1; then
        echo "错误：语音模型未展开，且 Git LFS 不可用" >&2
        exit 1
      fi
      echo "正在从共享 Git LFS 对象补全当前工作树的语音模型"
      git lfs checkout "Packages/LingoKit/Sources/SpeechKit/Resources/PocketTTS"
      Scripts/verify-bundled-voice-models.sh "$voice_model_stamp"
    fi
  fi

  # 每次生成可确保新增 Swift 文件立即进入工程；生成物已被 .gitignore 排除。
  xcodegen generate --quiet
}

lingotrip_simulator_udid() {
  local devices
  devices="$(xcrun simctl list devices available)"

  if [[ -n "${LINGOTRIP_SIMULATOR_UDID:-}" ]]; then
    if ! awk -v udid="$LINGOTRIP_SIMULATOR_UDID" 'index($0, udid) { found = 1 } END { exit !found }' <<< "$devices"; then
      echo "错误：指定的模拟器不可用：$LINGOTRIP_SIMULATOR_UDID" >&2
      return 1
    fi
    printf '%s\n' "$LINGOTRIP_SIMULATOR_UDID"
    return
  fi

  local udid
  udid="$(awk -F '[()]' '/iPhone/ && /\(Booted\)/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' <<< "$devices")"
  if [[ -z "$udid" ]]; then
    udid="$(awk -F '[()]' '/iPhone/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' <<< "$devices")"
  fi
  if [[ -z "$udid" ]]; then
    echo "错误：没有可用的 iPhone 模拟器" >&2
    return 1
  fi
  printf '%s\n' "$udid"
}

lingotrip_boot_simulator() {
  local udid="$1"
  local state
  state="$(xcrun simctl list devices | awk -v udid="$udid" 'index($0, udid) { if ($0 ~ /\(Booted\)/) print "Booted"; else print "Shutdown"; exit }')"
  if [[ "$state" != "Booted" ]]; then
    xcrun simctl boot "$udid"
  fi
  xcrun simctl bootstatus "$udid" -b
}

lingotrip_xcodebuild() {
  local scheme="$1"
  local udid="$2"
  shift 2

  xcodebuild \
    -project "$LINGOTRIP_REPO_ROOT/LingoTrip.xcodeproj" \
    -scheme "$scheme" \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$LINGOTRIP_DERIVED_DATA_PATH" \
    -clonedSourcePackagesDirPath "$LINGOTRIP_SOURCE_PACKAGES_PATH" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    CODE_SIGN_IDENTITY="-" \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    COMPILER_INDEX_STORE_ENABLE="${LINGOTRIP_INDEX_STORE_ENABLE:-NO}" \
    -quiet \
    "$@"
}
