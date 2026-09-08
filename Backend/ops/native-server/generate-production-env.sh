#!/bin/sh
set -eu

: "${DEEPSEEK_API_KEY:?Provide DEEPSEEK_API_KEY through the process environment}"

target="${1:-.env.production}"
if [ -e "${target}" ]; then
  echo "Refusing to overwrite existing ${target}" >&2
  exit 1
fi

umask 077
private_key_file="$(mktemp)"
public_key_file="$(mktemp)"
output_file="$(mktemp)"
trap 'rm -f "${private_key_file}" "${public_key_file}" "${output_file}"' EXIT

openssl genpkey -algorithm ED25519 -out "${private_key_file}" >/dev/null 2>&1
openssl pkey -in "${private_key_file}" -pubout -out "${public_key_file}" >/dev/null 2>&1

random_hex() {
  openssl rand -hex "${1}"
}

base64_file() {
  openssl base64 -A -in "${1}"
}

public_host="${PUBLIC_HOST:-rplearn.haruyuki.cn}"
app_version="${APP_VERSION:-$(git rev-parse --short=12 HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)}"
jwt_key_id="production-$(date -u +%Y%m%d)-$(random_hex 4)"

{
  printf 'PUBLIC_HOST=%s\n' "${public_host}"
  printf 'APP_VERSION=%s\n' "${app_version}"
  printf 'POSTGRES_PASSWORD=%s\n' "$(random_hex 24)"
  printf 'RUNTIME_DB_PASSWORD=%s\n' "$(random_hex 24)"
  printf 'REDIS_PASSWORD=%s\n' "$(random_hex 24)"
  printf 'AUTH_ISSUER=https://%s\n' "${public_host}"
  printf 'AUTH_AUDIENCE=lingotrip-clients\n'
  printf 'AUTH_ACTION_URL_BASE=https://%s/auth\n' "${public_host}"
  printf 'AUTH_EMAIL_FROM=LingoTrip <no-reply@%s>\n' "${public_host}"
  printf 'AUTH_TOKEN_HASH_PEPPER=%s\n' "$(random_hex 32)"
  printf 'AUTH_JWT_KEY_ID=%s\n' "${jwt_key_id}"
  printf 'AUTH_JWT_PRIVATE_KEY_BASE64=%s\n' "$(base64_file "${private_key_file}")"
  printf 'AUTH_JWT_PUBLIC_KEY_BASE64=%s\n' "$(base64_file "${public_key_file}")"
  printf 'AUTH_JWT_PREVIOUS_PUBLIC_KEYS=\n'
  printf 'JOB_PAYLOAD_ENCRYPTION_KEY_BASE64=%s\n' "$(openssl rand -base64 32 | tr -d '\n')"
  printf 'JOB_PAYLOAD_KEY_VERSION=production-v1\n'
  printf 'JOB_PAYLOAD_PREVIOUS_KEYS=\n'
  printf 'CORS_ALLOWED_ORIGINS=https://%s\n' "${public_host}"
  printf 'METRICS_ENABLED=true\n'
  printf 'METRICS_BEARER_TOKEN=%s\n' "$(random_hex 32)"
  printf 'ADMIN_API_ENABLED=false\n'
  printf 'ADMIN_API_KEYS=\n'
  printf 'DEEPSEEK_API_KEY=%s\n' "${DEEPSEEK_API_KEY}"
  printf 'DEEPSEEK_BASE_URL=https://api.deepseek.com\n'
  printf 'AI_DEEPSEEK_ALLOWED_MODELS=deepseek-v4-flash\n'
  printf 'AI_GUEST_ACCESS_ENABLED=true\n'
  printf 'MEDIA_STORAGE_ENABLED=true\n'
  printf 'MEDIA_S3_BUCKET=lingotrip-media\n'
  printf 'MEDIA_S3_REGION=us-east-1\n'
  printf 'MEDIA_S3_ENDPOINT=https://%s\n' "${public_host}"
  printf 'MEDIA_S3_FORCE_PATH_STYLE=true\n'
  printf 'MEDIA_S3_ACCESS_KEY_ID=%s\n' "$(random_hex 12)"
  printf 'MEDIA_S3_SECRET_ACCESS_KEY=%s\n' "$(random_hex 32)"
  printf 'SMTP_HOST=mailpit\n'
  printf 'SMTP_PORT=1025\n'
  printf 'SMTP_SECURE=false\n'
  printf 'SMTP_USER=\n'
  printf 'SMTP_PASSWORD=\n'
  printf 'APPLE_AUTH_ENABLED=false\n'
  printf 'APPLE_CLIENT_IDS=com.tiantian.lingotrip\n'
  printf 'APPLE_TEAM_ID=\n'
  printf 'APPLE_KEY_ID=\n'
  printf 'APPLE_PRIVATE_KEY_BASE64=\n'
  printf 'APPLE_CREDENTIAL_ENCRYPTION_KEY_BASE64=%s\n' "$(openssl rand -base64 32 | tr -d '\n')"
  printf 'APPLE_CREDENTIAL_KEY_VERSION=production-v1\n'
  printf 'APPLE_REDIRECT_URI=\n'
  printf 'APPLE_BILLING_ENABLED=false\n'
  printf 'APPLE_BILLING_BUNDLE_ID=com.tiantian.lingotrip\n'
  printf 'LOG_LEVEL=info\n'
  printf 'TRUST_PROXY=true\n'
  printf 'OTEL_TRACING_ENABLED=false\n'
} >"${output_file}"

mv "${output_file}" "${target}"
chmod 600 "${target}"
echo "Generated ${target} with mode 0600"
