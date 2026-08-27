#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

pocket_root="Packages/LingoKit/Sources/SpeechKit/Resources/PocketTTS/Models/pocket-tts/v2.1/english"
verification_stamp="${1:-}"

fail() {
  echo "错误：随包语音模型不完整或校验不匹配。请先执行 git lfs pull。" >&2
  exit 1
}

verify_file() {
  local root="$1"
  local relative_path="$2"
  local expected_size="$3"
  local expected_sha256="$4"
  local path="$root/$relative_path"

  [[ -f "$path" ]] || fail
  [[ "$(stat -f '%z' "$path")" == "$expected_size" ]] || fail
  [[ "$(shasum -a 256 "$path" | cut -d ' ' -f 1)" == "$expected_sha256" ]] || fail
}

pocket_file_count=$(find "$pocket_root" -type f | wc -l | tr -d ' ')
pocket_byte_count=$(find "$pocket_root" -type f -print0 \
  | xargs -0 stat -f '%z' \
  | awk '{sum += $1} END {printf "%.0f", sum}')

# 构建期可传入 DerivedData 内的校验戳。文件集合、总大小和修改时间均未变化时，
# 跳过约 288 MB 的重复 SHA-256 读取；直接调用本脚本时仍始终进行完整校验。
if [[ -n "$verification_stamp" ]] \
  && [[ -f "$verification_stamp" ]] \
  && [[ "$pocket_file_count" == "30" ]] \
  && [[ "$pocket_byte_count" == "331440634" ]] \
  && [[ -z "$(find "$pocket_root" -type f -newer "$verification_stamp" -print -quit)" ]]; then
  echo "随包语音模型校验缓存有效：TTS 30 个文件 / 331440634 字节。"
  exit 0
fi

verify_file "$pocket_root" \
  "cond_prefill.mlmodelc/weights/weight.bin" \
  "133237248" \
  "3a40a5ef3158ef91bfbf932be1c6ee44daca10a856fbb30b9a6720ad9424df8c"
verify_file "$pocket_root" \
  "flow_decoder_fused.mlmodelc/weights/weight.bin" \
  "19012608" \
  "f28a1bd0af940a195802e9d702c9e050f3e69d265e582f3d0fdf4001709eb30c"
verify_file "$pocket_root" \
  "flowlm_stepv2.mlmodelc/weights/weight.bin" \
  "76809280" \
  "5b7a9bbbc6ba5093cdfb55fb149c0d816191161ad866de5733406ebd7b01fba6"
verify_file "$pocket_root" \
  "mimi_decoder.mlmodelc/weights/weight.bin" \
  "41768256" \
  "c93d182f9ad8c1042ec8302093aabb4e310d76616932dd12720e03b5d07f7c64"
verify_file "$pocket_root" \
  "constants_bin/text_embed_table.bin" \
  "16388096" \
  "2512f9edd82ab0c68bb42a5fcd329a371eaf63ee6fb5275dfb1bc9536592bb0e"

[[ "$pocket_file_count" == "30" ]] || fail

[[ "$pocket_byte_count" == "331440634" ]] || fail

if [[ -n "$verification_stamp" ]]; then
  mkdir -p "$(dirname "$verification_stamp")"
  touch "$verification_stamp"
fi

echo "随包语音模型校验通过：TTS 30 个文件 / 331440634 字节。"
