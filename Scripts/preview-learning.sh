#!/usr/bin/env bash
# Isolated, zero-server-call replay prototype. No production records are reset.
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
mode="${1:-preview}"
case "$mode" in preview|build) ;; *) echo 'Usage: Scripts/preview-learning.sh [preview|build]'; exit 1;; esac
Scripts/preview.sh "$mode" contacts
source Scripts/lib/ios-worktree.sh
lingotrip_acquire_pipeline_lock
udid="$(lingotrip_simulator_udid)"
SIMCTL_CHILD_UI_TEST_SKIP_ONBOARDING=1 \
SIMCTL_CHILD_UI_TEST_REQUIRE_AUTHENTICATION=0 \
SIMCTL_CHILD_UI_TEST_DISABLE_BACKGROUND_REFRESH=1 \
SIMCTL_CHILD_UI_TEST_WELCOME_CAPTURE=1 \
SIMCTL_CHILD_UI_TEST_NATIVE_CAPTURE=learningLab \
SIMCTL_CHILD_UI_TEST_LEARNING_NAMESPACE=interactive-preview \
SIMCTL_CHILD_UI_TEST_TAB=contacts \
SIMCTL_CHILD_LINGOTRIP_BACKEND_URL=http://127.0.0.1:9 \
  xcrun simctl launch --terminate-running-process "$udid" com.tiantian.lingotrip
