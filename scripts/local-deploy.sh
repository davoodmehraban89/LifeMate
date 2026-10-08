#!/usr/bin/env bash
# Local Docker only. This script never SSHs, modifies DNS or creates accounts.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
umask 077
prebuilt_web=no
if [[ "${1:-}" == '--prebuilt-web' ]]; then
  prebuilt_web=yes
  shift
fi
if [[ "${1:-}" == '--init' ]]; then
  origin="${2:?Usage: scripts/local-deploy.sh --init https://LAN-IP}"
  [[ "$origin" =~ ^https://([A-Za-z0-9.-]+|\[[0-9A-Fa-f:]+\])(:[0-9]+)?$ ]] || { echo 'Use one HTTPS origin without a path or credentials' >&2; exit 1; }
  https_port=443
  if [[ "$origin" =~ :([0-9]+)$ ]]; then https_port="${BASH_REMATCH[1]}"; fi
  [[ "$https_port" -ge 1 && "$https_port" -le 65535 ]] || { echo 'Invalid HTTPS port' >&2; exit 1; }
  if [[ -f .env ]]; then
    echo '.env already exists; preserving it. Edit it deliberately to change settings.'
  else
    command -v openssl >/dev/null || { echo 'openssl is required to generate secrets' >&2; exit 1; }
    db_secret="$(openssl rand -hex 32)"
    jwt_secret="$(openssl rand -hex 48)"
    sed -e "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$db_secret|" \
        -e "s|^JWT_SECRET=.*|JWT_SECRET=$jwt_secret|" \
        -e "s|^PUBLIC_APP_URL=.*|PUBLIC_APP_URL=$origin|" \
        -e "s|^CORS_ORIGINS=.*|CORS_ORIGINS=$origin|" \
        -e "s|^HTTPS_PORT=.*|HTTPS_PORT=$https_port|" .env.example >.env
    chmod 600 .env
    unset db_secret jwt_secret
    echo 'Created private .env with random local secrets.'
  fi
fi
[[ -f .env ]] || { echo 'Create .env first, or use --init https://LAN-IP' >&2; exit 1; }
if grep -Eq '^((POSTGRES_PASSWORD|JWT_SECRET)=CHANGE_ME|JWT_SECRET=.{0,31}$)' .env; then
  echo 'Replace placeholder/short secrets in .env' >&2; exit 1
fi
if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
  endpoint="$(docker context inspect "$DOCKER_CONTEXT" --format '{{.Endpoints.docker.Host}}')"
else
  endpoint="${DOCKER_HOST:-$(docker context inspect --format '{{.Endpoints.docker.Host}}')}"
fi
case "$endpoint" in unix://*|npipe://*) ;; *) echo 'Refusing a remote Docker endpoint; this command is local only.' >&2; exit 1;; esac
docker info >/dev/null
docker compose config --quiet
cert_file="$(sed -n 's/^TLS_CERT_PATH=//p' .env)"
key_file="$(sed -n 's/^TLS_KEY_PATH=//p' .env)"
[[ -f "$cert_file" && -f "$key_file" ]] || { echo 'Create the configured TLS certificate/key first' >&2; exit 1; }
# These bind-mounted files contain public client configuration/downloads. Keep
# private .env and TLS keys unchanged; nginx workers must read only this data.
chmod 755 deployment deployment/downloads
chmod 644 deployment/runtime-config.json
find deployment/downloads -maxdepth 1 -type f -name '*.apk' -exec chmod 644 {} +
# nginx validates the certificate/key pair on startup.
compose_build=(-f docker-compose.yml)
if [[ "$prebuilt_web" == yes ]]; then
  command -v node >/dev/null || { echo 'Node >=22 required to validate the prebuilt web artifact' >&2; exit 1; }
  node scripts/prebuilt-web-check.mjs apps/lifemate
  compose_build+=(-f docker-compose.prebuilt-web.yml)
fi
if [[ -n "${BUILD_CA_FILE:-}" ]]; then
  [[ -f "$BUILD_CA_FILE" ]] || { echo 'BUILD_CA_FILE must be a public CA certificate file' >&2; exit 1; }
  if grep -q 'PRIVATE KEY' "$BUILD_CA_FILE"; then echo 'Private key forbidden in build CA input' >&2; exit 1; fi
  compose_build+=(-f docker-compose.build-proxy.yml)
  docker compose "${compose_build[@]}" build api gateway backup
else
  docker compose "${compose_build[@]}" build --build-arg HTTP_PROXY --build-arg HTTPS_PROXY api gateway backup
fi
docker compose up -d --wait --wait-timeout 120 postgres
docker compose run --rm migrate
docker compose up -d --wait --wait-timeout 180 api gateway backup
docker compose ps
echo 'Local stack started. Run the HTTPS smoke test; health alone does not prove family CRUD.'
