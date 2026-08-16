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

# Progress / display options
# SHOW_LOGS=1 will tail docker compose logs briefly after starting (useful to see progress)
SHOW_LOGS="${SHOW_LOGS:-0}"

info(){ printf "\033[0;34m[info]\033[0m %s\n" "$*"; }
warn(){ printf "\033[0;33m[warn]\033[0m %s\n" "$*"; }
err(){ printf "\033[0;31m[err]\033[0m %s\n" "$*"; exit 1; }

# normalize HEALTH_PATH to begin with /
case "$HEALTH_PATH" in
  "") HEALTH_PATH="/";;
  /*) ;; # ok
  *) HEALTH_PATH="/${HEALTH_PATH}";;
esac

# spinner for background tasks
_spinner_pid=0
start_spinner(){
  local msg="$1"
  local delay=0.1
  local spinstr="|/-\\"
  printf "%s " "$msg"
  (
    while :; do
      for c in $spinstr; do
        printf "%s" "$c"
        sleep $delay
        printf "\b"
      done
    done
  ) &
  _spinner_pid=$!
  disown
}
stop_spinner(){
  local exitcode=${1:-0}
  if [ "${_spinner_pid}" -ne 0 ]; then
    kill "${_spinner_pid}" >/dev/null 2>&1 || true
    wait "${_spinner_pid}" 2>/dev/null || true
    _spinner_pid=0
  fi
  if [ $exitcode -eq 0 ]; then
    printf " ✅\n"
  else
    printf " ❌ (code=%d)\n" "$exitcode"
  fi
}

# run a command with spinner (no streaming of stdout/stderr)
run_with_spinner(){
  local msg="$1"; shift
  start_spinner "$msg"
  ("$@") >/dev/null 2>&1 &
  local pid=$!
  wait $pid
  local rc=$?
  stop_spinner $rc
  return $rc
}

# check commands
command -v git >/dev/null 2>&1 || err "git is required. Install Git first."
command -v docker >/dev/null 2>&1 || err "docker is required. Install Docker (Docker Desktop / Engine)."
# docker compose: prefer 'docker compose' (v2) else docker-compose
if command -v docker-compose >/dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker-compose"
else
  DOCKER_COMPOSE_CMD="docker compose"
fi

step=1
print_step(){
  printf "\n> Step %d: %s\n" "$step" "$1"
  step=$((step+1))
}

print_step "Clone or update repository"
if [ ! -d "$REPO_DIR" ]; then
  # clone with spinner
  run_with_spinner "Cloning $REPO -> $REPO_DIR..." git clone --depth 1 "$REPO" "$REPO_DIR" || true
else
  info "Directory exists, fetching latest"
  # fetch/pull with spinner
  run_with_spinner "Fetching latest in $REPO_DIR..." bash -c "(cd \"$REPO_DIR\" && git fetch --all && git pull --ff-only)" || true
fi

cd "$REPO_DIR"

print_step "Prepare environment (.env & data)"
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

print_step "Build docker images (streaming output)"
# Prefer docker compose build with progress support if available, else plain build
BUILD_CMD=("$DOCKER_COMPOSE_CMD" build)
if "$DOCKER_COMPOSE_CMD" build --help 2>/dev/null | grep -q -- '--progress'; then
  BUILD_CMD=("$DOCKER_COMPOSE_CMD" build --progress=plain)
fi
# Stream build output (no spinner) so user sees progress
info "Running: ${BUILD_CMD[*]}"
"${BUILD_CMD[@]}"
BUILD_RC=$?
if [ $BUILD_RC -ne 0 ]; then
  warn "Build returned non-zero ($BUILD_RC). You can inspect build logs with: $DOCKER_COMPOSE_CMD build"
fi

print_step "Start services (docker compose up -d)"
run_with_spinner "Starting services..." $DOCKER_COMPOSE_CMD up --build -d
UP_RC=$?
if [ $UP_RC -ne 0 ]; then
  err "Failed to start services (code $UP_RC). Check: $DOCKER_COMPOSE_CMD logs"
fi

# Optionally show brief logs to indicate progress
if [ "${SHOW_LOGS}" = "1" ]; then
  print_step "Showing recent logs (brief)"
  # tail logs for a short period to show startup progress
  ( $DOCKER_COMPOSE_CMD logs --no-color --tail=200 -f & ) &
  LOG_PID=$!
  # show logs for 8 seconds
  sleep 8
  kill "$LOG_PID" >/dev/null 2>&1 || true
fi

# Readiness check (strict): prefer HTTP health endpoint, fallback to TCP port
URL_BASE="http://localhost:${PORT}"
HEALTH_URL="${URL_BASE}${HEALTH_PATH}"

print_step "Wait for application readiness"
info "Waiting up to ${MAX_WAIT}s for the service at ${HEALTH_URL} (retries=${RETRIES}, interval=${WAIT_INTERVAL}s)..."

ready=false
attempt=0
while [ "$attempt" -lt "$RETRIES" ]; do
  if command -v curl >/dev/null 2>&1; then
    HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "${HEALTH_URL}" 2>/dev/null || echo "000")
    if echo "$HTTP_CODE" | grep -E '^[23][0-9][0-9]$' >/dev/null 2>&1; then
      info "Service responded at ${HEALTH_URL} (HTTP ${HTTP_CODE})"
      ready=true
      break
    else
      info "Attempt $((attempt+1))/${RETRIES}: ${HEALTH_URL} returned HTTP ${HTTP_CODE}; retrying in ${WAIT_INTERVAL}s..."
    fi
  else
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
  exit 2
else
  info "Open the web UI at: ${URL_BASE}/"
  info "Use the AUTH_PASSWORD value in .env to sign in (if set)."
fi

info "To follow logs: ${DOCKER_COMPOSE_CMD} logs -f"
info "To stop: ${DOCKER_COMPOSE_CMD} down"
