#!/bin/sh
set -eu

smoke_image_ref=${1:?container image reference is required}
smoke_port=${SMOKE_PORT:-18082}
smoke_container_name="lingotrip-backend-smoke-$$"

# Invoked indirectly by the EXIT/INT/TERM trap.
# shellcheck disable=SC2329
cleanup_smoke_container() {
  docker rm --force "$smoke_container_name" >/dev/null 2>&1 || true
}
trap cleanup_smoke_container EXIT INT TERM

docker run \
  --add-host host.docker.internal:host-gateway \
  --detach \
  --name "$smoke_container_name" \
  --publish "127.0.0.1:${smoke_port}:${smoke_port}" \
  --env DATABASE_URL=postgres://lingotrip:lingotrip_dev@host.docker.internal:54329/lingotrip \
  --env HOST=0.0.0.0 \
  --env NODE_ENV=development \
  --env PORT="$smoke_port" \
  --env REDIS_URL=redis://host.docker.internal:63799 \
  "$smoke_image_ref" >/dev/null

smoke_attempt=1
while [ "$smoke_attempt" -le 30 ]; do
  if curl --fail --silent --show-error \
    "http://127.0.0.1:${smoke_port}/health/ready" >/dev/null 2>&1; then
    exit 0
  fi
  if ! docker inspect "$smoke_container_name" \
    --format '{{.State.Running}}' | grep --quiet true; then
    docker logs "$smoke_container_name"
    exit 1
  fi
  smoke_attempt=$((smoke_attempt + 1))
  sleep 1
done

docker logs "$smoke_container_name"
exit 1
