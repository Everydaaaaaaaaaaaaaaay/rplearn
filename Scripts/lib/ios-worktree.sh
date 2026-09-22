#!/usr/bin/env bash

# 多工作树共用的 iOS 构建基础设施。
# 调用方应先启用 `set -euo pipefail`，再 source 本文件。

LINGOTRIP_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINGOTRIP_DERIVED_DATA_PATH="${LINGOTRIP_DERIVED_DATA_PATH:-$LINGOTRIP_REPO_ROOT/build/DerivedData}"
LINGOTRIP_SOURCE_PACKAGES_PATH="${LINGOTRIP_SOURCE_PACKAGES_PATH:-$LINGOTRIP_REPO_ROOT/build/SourcePackages}"
LINGOTRIP_PIPELINE_LOCK_DIR="$LINGOTRIP_REPO_ROOT/build/locks/ios-pipeline.lock"
LINGOTRIP_PIPELINE_LOCK_HELD=0

lingotrip_require_command() {
  local command_name="$1"
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "错误：缺少命令 $command_name" >&2
    exit 1
  fi
}

# 包目标会同时留下 Products/<Name>.swiftmodule（App 目标使用的静态库模块）和
# PackageFrameworks/<Name>.framework 里的动态副本。测试构建重新编译包目标到
# PackageFrameworks，但编译参数里 -I Products 优先，于是 App 构建留下的旧副本会
# 遮蔽新模块，新增公开符号时表现为“cannot find type in scope”。
# 测试构建前移除已有动态框架对应的静态镜像；不能只比较旧产物时间，
# 因为本次构建才会更新动态框架。App 构建之后会按需重新生成镜像。
lingotrip_clear_shadowed_package_modules() {
  local products="$LINGOTRIP_DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator"
  local frameworks="$products/PackageFrameworks"
  if [[ ! -d "$products" || ! -d "$frameworks" ]]; then
    return 0
  fi
  local framework name mirror mirror_module framework_module
  for framework in "$frameworks"/*.framework; do
    [[ -d "$framework" ]] || continue
    name="$(basename "$framework" .framework)"
    mirror="$products/$name.swiftmodule"
    mirror_module="$mirror/arm64-apple-ios-simulator.swiftmodule"
    framework_module="$framework/Modules/$name.swiftmodule/arm64-apple-ios-simulator.swiftmodule"
    if [[ -f "$mirror_module" && -f "$framework_module" ]]; then
      find "$mirror" -depth -delete 2>/dev/null || true
    fi
  done
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
  mkdir -p "$(dirname "$LINGOTRIP_PIPELINE_LOCK_DIR")" "$LINGOTRIP_SOURCE_PACKAGES_PATH"

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
      echo "当前工作树已有构建或模拟器操作，正在排队：$owner_worktree"
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

lingotrip_package_cache_ready() {
  [[ -f "$LINGOTRIP_SOURCE_PACKAGES_PATH/checkouts/FluidAudio/Package.swift" ]]
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
      git lfs checkout "Packages/LingoKit/Sources/SpeechKit/Resources/Supertonic3"
      Scripts/verify-bundled-voice-models.sh "$voice_model_stamp"
    fi
  fi

  # 每次生成可确保新增 Swift 文件立即进入工程；生成物已被 .gitignore 排除。
  xcodegen generate --quiet
}

lingotrip_simulator_udid() {
  local devices
  devices="$(xcrun simctl list devices available)"

  local configured_udid="${LINGOTRIP_SIMULATOR_UDID:-}"
  if [[ -z "$configured_udid" ]]; then
    configured_udid="$(git -C "$LINGOTRIP_REPO_ROOT" config --worktree --get lingotrip.simulatorUDID 2>/dev/null || true)"
  fi

  if [[ -n "$configured_udid" ]]; then
    if ! awk -v udid="$configured_udid" 'index($0, udid) { found = 1 } END { exit !found }' <<< "$devices"; then
      echo "错误：当前工作树绑定的模拟器不可用：$configured_udid" >&2
      return 1
    fi
    printf '%s\n' "$configured_udid"
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

  local is_test=0 result_bundle="" previous_argument="" argument
  for argument in "$@"; do
    if [[ "$argument" == "test" || "$argument" == "test-without-building" ]]; then
      is_test=1
    fi
    if [[ "$previous_argument" == "-resultBundlePath" ]]; then
      result_bundle="$argument"
    fi
    previous_argument="$argument"
  done

  local xcodebuild_arguments=(
    -project "$LINGOTRIP_REPO_ROOT/LingoTrip.xcodeproj"
    -scheme "$scheme"
    -destination "platform=iOS Simulator,id=$udid"
    -derivedDataPath "$LINGOTRIP_DERIVED_DATA_PATH"
    -clonedSourcePackagesDirPath "$LINGOTRIP_SOURCE_PACKAGES_PATH"
    CODE_SIGNING_ALLOWED=YES
    CODE_SIGNING_REQUIRED=YES
    CODE_SIGN_IDENTITY="-"
    DEVELOPMENT_TEAM=""
    PROVISIONING_PROFILE_SPECIFIER=""
    COMPILER_INDEX_STORE_ENABLE="${LINGOTRIP_INDEX_STORE_ENABLE:-NO}"
    -quiet
  )
  if lingotrip_package_cache_ready; then
    # 完整缓存只读取 Package.resolved，避免每次构建访问远端或与其他工作树争用。
    xcodebuild_arguments+=(
      -disableAutomaticPackageResolution
      -onlyUsePackageVersionsFromResolvedFile
    )
  else
    echo "当前工作树首次准备 Swift Package 依赖；完成后后续构建将使用本地锁定缓存"
  fi

  if [[ "$is_test" == "1" && -z "$result_bundle" ]]; then
    mkdir -p "$LINGOTRIP_DERIVED_DATA_PATH/VerificationResults"
    result_bundle="$LINGOTRIP_DERIVED_DATA_PATH/VerificationResults/$(date -u '+%Y%m%dT%H%M%SZ')-$$.xcresult"
    xcodebuild_arguments+=(-resultBundlePath "$result_bundle")
  fi

  xcodebuild "${xcodebuild_arguments[@]}" "$@"
  if [[ "$is_test" == "1" ]]; then
    # Xcode can exit successfully when -only-testing matches nothing.
    # A skipped live suite also cannot count as an executed verification.
    xcrun xcresulttool get test-results summary --path "$result_bundle" |
      python3 -c 'import json, sys
summary = json.load(sys.stdin)
passed = summary.get("passedTests", 0)
failed = summary.get("failedTests", 0)
skipped = summary.get("skippedTests", 0)
print(f"测试结果：{passed} 通过，{failed} 失败，{skipped} 跳过")
if passed + failed == 0:
    sys.exit("错误：没有实际执行测试，请检查 -only-testing 筛选与 live 开关。")
if failed:
    sys.exit("错误：结果包仍包含失败测试。")'
    echo "测试证据：$result_bundle"
  fi
}
