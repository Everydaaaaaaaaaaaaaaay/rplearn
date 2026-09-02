#!/usr/bin/env bash
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

supertonic_root="Packages/LingoKit/Sources/SpeechKit/Resources/Supertonic3/Models/supertonic-3"
verification_stamp="${1:-}"

fail() {
  echo "错误：随包 Supertonic-3 模型不完整或校验不匹配。请先执行 git lfs pull。" >&2
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

supertonic_file_count=$(find "$supertonic_root" -type f | wc -l | tr -d ' ')
supertonic_byte_count=$(find "$supertonic_root" -type f -print0 \
  | xargs -0 stat -f '%z' \
  | awk '{sum += $1} END {printf "%.0f", sum}')

# 构建期可传入 DerivedData 内的校验戳。文件集合、总大小和修改时间均未变化时，
# 跳过重复 SHA-256 读取；直接调用本脚本时仍始终进行完整校验。
if [[ -n "$verification_stamp" ]] \
  && [[ -f "$verification_stamp" ]] \
  && [[ "$supertonic_file_count" == "38" ]] \
  && [[ "$supertonic_byte_count" == "171602494" ]] \
  && [[ -z "$(find "$supertonic_root" -type f -newer "$verification_stamp" -print -quit)" ]]; then
  echo "随包语音模型校验缓存有效：Supertonic 171602494 字节。"
  exit 0
fi

verify_file "$supertonic_root" \
  "TextEncoder.mlmodelc/weights/weight.bin" \
  "18022016" \
  "7c7afa5d02426a8a363c9cef0e27ce64a5c57a67d1a59f60aac0ac58ffb9877f"
verify_file "$supertonic_root" \
  "DurationPredictor.mlmodelc/weights/weight.bin" \
  "1797952" \
  "7f709c544087966d6b2538ac50b7a4014d6e1049e21d713cf3bc71c4c5b9307c"
verify_file "$supertonic_root" \
  "Vocoder.mlmodelc/weights/weight.bin" \
  "50672512" \
  "b45e4c17a45cc4de30dcedae9f662548aa35f8f9763632c342b8bbef3089fcee"
verify_file "$supertonic_root" \
  "VectorEstimatorVariants/VectorEstimator_L128_int4.mlmodelc/weights/weight.bin" \
  "32166112" \
  "1ef6a7d8fefe4b785cbb96532ce2c1bf479471bbeabcec04c2e893550ea8e2a3"
verify_file "$supertonic_root" \
  "VectorEstimatorVariants/VectorEstimator_L256_int4.mlmodelc/weights/weight.bin" \
  "32167200" \
  "71ca80054430e290efa804aa88a3c862d6edb901367af8dd7db5a70f49ae623c"
verify_file "$supertonic_root" \
  "VectorEstimatorVariants/VectorEstimator_L512_int4.mlmodelc/weights/weight.bin" \
  "32168224" \
  "fd60d308e99c5be4796981f54bff2e0fe6983706bd31b48f331ddcd3239524a9"

[[ "$supertonic_file_count" == "38" ]] || fail
[[ "$supertonic_byte_count" == "171602494" ]] || fail

if [[ -n "$verification_stamp" ]]; then
  mkdir -p "$(dirname "$verification_stamp")"
  touch "$verification_stamp"
fi

echo "随包语音模型校验通过：Supertonic 171602494 字节。"
