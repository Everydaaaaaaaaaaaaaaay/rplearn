#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

asr_root="Packages/LingoKit/Sources/RealtimeVoiceKit/Resources/RealtimeASRModels"
pocket_root="Packages/LingoKit/Sources/SpeechKit/Resources/PocketTTS/Models/pocket-tts-coreml/v2.1/english"

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

verify_file "$asr_root" \
  "ParakeetEOU320/decoder.mlmodelc/weights/weight.bin" \
  "7873600" \
  "0b4cacecdcd9df79ab1e56de67230baf5a8664d2afe0bb8f3408eefa972cb2f4"
verify_file "$asr_root" \
  "ParakeetEOU320/joint_decision.mlmodelc/weights/weight.bin" \
  "2794182" \
  "7039b2010a269153f5a96edf28637f921a86ef8822f248f2d6712f7a6bce84b4"
verify_file "$asr_root" \
  "ParakeetEOU320/streaming_encoder.mlmodelc/weights/weight.bin" \
  "212865856" \
  "ff553fcb4f4560cfce1e558e16bb9d856e4b4f6a4c08f800d5c126fce4196822"
verify_file "$asr_root" \
  "SenseVoiceSmallINT8/SenseVoicePreprocessor.mlmodelc/weights/weight.bin" \
  "3037504" \
  "69c630a115da5e4db36ec41662f0b776c0ef33ec6776d86f8cdaaba022518396"
verify_file "$asr_root" \
  "SenseVoiceSmallINT8/SenseVoiceSmall_int8.mlmodelc/weights/weight.bin" \
  "235373118" \
  "dab122c65d5043cba5b47561d5c1d3a049dd123c662e802d9dbce8fdd0505a38"

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

asr_file_count=$(find \
  "$asr_root/ParakeetEOU320" \
  "$asr_root/SenseVoiceSmallINT8" \
  -type f | wc -l | tr -d ' ')
[[ "$asr_file_count" == "25" ]] || fail

asr_byte_count=$(find \
  "$asr_root/ParakeetEOU320" \
  "$asr_root/SenseVoiceSmallINT8" \
  -type f -print0 | xargs -0 stat -f '%z' | awk '{sum += $1} END {printf "%.0f", sum}')
[[ "$asr_byte_count" == "464151912" ]] || fail

pocket_file_count=$(find "$pocket_root" -type f | wc -l | tr -d ' ')
[[ "$pocket_file_count" == "30" ]] || fail

pocket_byte_count=$(find "$pocket_root" -type f -print0 \
  | xargs -0 stat -f '%z' \
  | awk '{sum += $1} END {printf "%.0f", sum}')
[[ "$pocket_byte_count" == "331440634" ]] || fail

echo "随包语音模型校验通过：ASR 25 个文件 / 464151912 字节，TTS 30 个文件 / 331440634 字节。"
