#!/bin/sh
set -e

PROJECT=${COMPOSE_PROJECT_NAME:-fleet-telemetry}

log() {
  echo "[certbot deploy-hook] $*"
}

docker_api() {
  local path="$1"
  curl --unix-socket /var/run/docker.sock -X POST "http://localhost${path}" >/dev/null 2>&1
}

# Reload nginx to pick up renewed certificates.
docker_api "/containers/${PROJECT}_nginx_1/kill?signal=HUP" || log "nginx reload signal failed"

# Restart services that load certs on boot.
docker_api "/containers/${PROJECT}_telemetry_1/restart" || log "telemetry restart failed"
docker_api "/containers/${PROJECT}_tesla_http_proxy_1/restart" || log "vehicle proxy restart failed"

