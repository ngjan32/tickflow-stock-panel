#!/usr/bin/env bash
set -euo pipefail

REPO="https://github.com/ngjan32/tickflow-stock-panel.git"
REPO_DIR="${1:-tickflow-stock-panel}"
PORT="${PORT:-3018}"
MAX_WAIT=60  # seconds to wait for HTTP 200

# Readiness configuration (customize via env vars)
HEALTH_PATH="${HEALTH_PATH:-/}"         # health check path on the server (e.g. /health, /ready). Leading slash optional.
WAIT_INTERVAL="${WAIT_INTERVAL:-2}"     # seconds between attempts
# If RETRIES not set, derive from MAX_WAIT/WAIT_INTERVAL (minimum 1)
if [ -z "${RETRIES:-}" ]; then
  RETRIES=$(( (MAX_WAIT + WAIT_INTERVAL - 1) / WAIT_INTERVAL ))
fi

info(){ printf "\033[0;34m[info]\033[0m %s\n" "$*"; }
warn(){ printf "\033[0;33m[warn]\033[0m %s\n" "$*"; }
err(){ printf "\033[0;31m[err]\033[0m %s\n" "$*"; exit 1; }

# normalize HEALTH_PATH to begin with /
case "$HEALTH_PATH" in
  "") HEALTH_PATH="/";;
  /*) ;; # ok
  *) HEALTH_PATH="/${HEALTH_PATH}";;
esac

# check commands
command -v git >/dev/null 2>&1 || err "git is required. Install Git first."
command -v docker >/dev/null 2>&1 || err "docker is required. Install Docker (Docker Desktop / Engine)."
# docker compose: prefer 'docker compose' (v2) else docker-compose
if command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
else
  DOCKER_COMPOSE_CMD="docker compose"
fi

info "Clone repo (if missing): $REPO -> $REPO_DIR"
if [ ! -d "$REPO_DIR" ]; then
  git clone "$REPO" "$REPO_DIR"
else
  info "Directory exists, fetching latest"
  (cd "$REPO_DIR" && git fetch --all && git pull --ff-only) || true
fi

cd "$REPO_DIR"

# Ensure .env
if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    cp .env.example .env
    warn "Copied .env.example -> .env. Edit .env to add secrets if desired."
  else
    warn "No .env.example found. Creating empty .env"
    touch .env
  fi
else
  info ".env already present"
fi

# If AUTH_PASSWORD empty, generate and insert one (one-time)
AUTH_LINE=$(grep -n '^AUTH_PASSWORD=' .env || true)
if [ -z "$AUTH_LINE" ]; then
  echo "AUTH_PASSWORD=" >> .env
  AUTH_LINE=$(grep -n '^AUTH_PASSWORD=' .env || true)
fi

CURRENT_AUTH=$(awk -F= '/^AUTH_PASSWORD=/ {print substr($0, index($0,$2))}' .env | sed 's/^=//')
if [ -z "$CURRENT_AUTH" ]; then
  # generate password (prefer openssl)
  if command -v openssl >/dev/null 2>&1; then
    NEWPW=$(openssl rand -base64 12)
  else
    NEWPW=$(date +%s | sha256sum | cut -c1-12)
  fi
  # portable sed in-place: use backup then move
  sed -E "s/^AUTH_PASSWORD=.*/AUTH_PASSWORD=${NEWPW}/" .env > .env.tmp && mv .env.tmp .env
  info "Generated and wrote AUTH_PASSWORD to .env (one-time). Password: ${NEWPW}"
else
  info "AUTH_PASSWORD already set in .env (not changed)."
fi

# Ensure data dir exists and correct permission
mkdir -p data
chmod 700 data || true

# Ensure scripts are executable (local runtime)
if [ -f scripts/setup-and-run.sh ]; then
  chmod +x scripts/setup-and-run.sh || true
fi

info "Starting services with Docker Compose (this will build images)..."
# start detached
$DOCKER_COMPOSE_CMD up --build -d

# Readiness check (strict): prefer HTTP health endpoint, fallback to TCP port
URL_BASE="http://localhost:${PORT}"
HEALTH_URL="${URL_BASE}${HEALTH_PATH}"

info "Waiting up to ${MAX_WAIT}s for the service at ${HEALTH_URL} (retries=${RETRIES}, interval=${WAIT_INTERVAL}s)..."

ready=false
attempt=0
while [ "$attempt" -lt "$RETRIES" ]; do
  if command -v curl >/dev/null 2>&1; then
    # Use curl to fetch health endpoint and accept 2xx or 3xx as success
    # -sS: silent but show errors; -o /dev/null: discard body; -w '%{http_code}': output status code
    HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "${HEALTH_URL}" 2>/dev/null || echo "000")
    # success if code starts with 2 or 3
    if echo "$HTTP_CODE" | grep -E '^[23][0-9][0-9]$' >/dev/null 2>&1; then
      info "Service responded at ${HEALTH_URL} (HTTP ${HTTP_CODE})"
      ready=true
      break
    else
      info "Attempt $((attempt+1))/${RETRIES}: ${HEALTH_URL} returned HTTP ${HTTP_CODE}; retrying in ${WAIT_INTERVAL}s..."
    fi
  else
    # curl not available, fallback to TCP health check (port open)
    if (echo > /dev/tcp/localhost/"${PORT}") >/dev/null 2>&1; then
      info "Port ${PORT} is open (tcp). Service may be up."
      ready=true
      break
    else
      info "Attempt $((attempt+1))/${RETRIES}: port ${PORT} not open yet; retrying in ${WAIT_INTERVAL}s..."
    fi
  fi

  attempt=$((attempt + 1))
  sleep "${WAIT_INTERVAL}"
done

if [ "${ready}" != "true" ]; then
  warn "Timed out waiting for service. Check logs: ${DOCKER_COMPOSE_CMD} logs -f"
else
  info "Open the web UI at: ${URL_BASE}/"
  info "Use the AUTH_PASSWORD value in .env to sign in (if set)."
fi

info "To follow logs: ${DOCKER_COMPOSE_CMD} logs -f"
info "To stop: ${DOCKER_COMPOSE_CMD} down"
