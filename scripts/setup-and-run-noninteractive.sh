#!/usr/bin/env bash
# setup-and-run-noninteractive.sh
# Non-interactive helper to prepare and run tickflow-stock-panel on Linux.
# Usage (example):
# MODE=docker ./scripts/setup-and-run-noninteractive.sh
# MODE=dev AUTO_INSTALL=yes ./scripts/setup-and-run-noninteractive.sh
# Environment variables:
# - MODE: "docker" (default) or "dev"
# - REPO_DIR: path to clone repo into (default: tickflow-stock-panel)
# - REPO_URL: repository URL (default set below)
# - AUTO_INSTALL: "yes" to allow installing system packages via sudo non-interactively
# - SKIP_ENV_CHECK: "yes" to skip creating .env when missing
# - CODEX_HOME_HOST: optional, set in .env if provided
set -euo pipefail
IFS=$'\n\t'

REPO_URL="https://github.com/ngjan32/tickflow-stock-panel.git"
REPO_DIR="${REPO_DIR:-tickflow-stock-panel}"
MODE="${MODE:-docker}"
AUTO_INSTALL="${AUTO_INSTALL:-no}"
SKIP_ENV_CHECK="${SKIP_ENV_CHECK:-no}"

log() { echo "[setup] $*"; }
err() { echo "[error] $*" >&2; }

# helper: run apt-get non-interactively
apt_install() {
  if [ "$AUTO_INSTALL" != "yes" ]; then
    err "AUTO_INSTALL is not 'yes' — refusing to install system packages non-interactively"
    exit 1
  fi
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
}

# Clone or update repo
if [ -d "$REPO_DIR/.git" ]; then
  log "Repository exists at $REPO_DIR — fetching latest"
  cd "$REPO_DIR"
  git fetch --all --prune
  git pull --ff-only || true
else
  log "Cloning repository into $REPO_DIR"
  git clone "$REPO_URL" "$REPO_DIR"
  cd "$REPO_DIR"
fi

# Ensure scripts dir exists
mkdir -p scripts

# Ensure .env exists (copy from .env.example) unless skipped
if [ ! -f .env ] && [ "$SKIP_ENV_CHECK" != "yes" ]; then
  if [ -f .env.example ]; then
    cp .env.example .env
    log "Created .env from .env.example."
    # Optionally set CODEX_HOME_HOST if provided
    if [ -n "${CODEX_HOME_HOST:-}" ]; then
      # replace or append
      if grep -q '^CODEX_HOME_HOST=' .env 2>/dev/null; then
        sed -i "s|^CODEX_HOME_HOST=.*|CODEX_HOME_HOST=${CODEX_HOME_HOST}|" .env
      else
        echo "CODEX_HOME_HOST=${CODEX_HOME_HOST}" >> .env
      fi
    fi
    log "Note: .env may contain placeholders; edit it to add TICKFLOW_API_KEY/AI_API_KEY if needed."
  else
    cat > .env <<'EOF'
TICKFLOW_API_KEY=
AI_PROVIDER=openai_compat
AI_BASE_URL=https://api.deepseek.com/v1
AI_API_KEY=
AI_MODEL=deepseek-chat
PORT=3018
DATA_DIR=./data
EOF
    log ".env not found; wrote minimal .env. Edit to add keys."
  fi
else
  log ".env exists or SKIP_ENV_CHECK=yes — skipping .env creation."
fi

# MODE dispatch
if [ "$MODE" = "docker" ]; then
  log "Running in Docker mode (non-interactive)"
  # Ensure docker
  if ! command -v docker >/dev/null 2>&1; then
    log "docker not found"
    if [ "$AUTO_INSTALL" = "yes" ]; then
      log "Installing Docker using get-docker.sh (requires sudo)"
      curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
      sudo sh /tmp/get-docker.sh
      rm -f /tmp/get-docker.sh
      sudo usermod -aG docker "$USER" || true
      log "Added $USER to docker group; you may need to relogin for group change to take effect"
    else
      err "docker not installed and AUTO_INSTALL!=yes. Install Docker or set AUTO_INSTALL=yes to allow automated install."
      exit 1
    fi
  else
    log "docker present"
  fi

  # docker compose availability
  COMPOSE_CMD=""
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
  else
    # try to install compose plugin via apt if allowed
    if [ "$AUTO_INSTALL" = "yes" ]; then
      log "Installing docker-compose-plugin via apt"
      apt_install docker-compose-plugin || true
      if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
      fi
    fi
  fi

  if [ -z "$COMPOSE_CMD" ]; then
    err "docker compose is not available. Please install Docker Compose."
    exit 1
  fi

  log "Starting containers with: $COMPOSE_CMD up --build -d"
  $COMPOSE_CMD up --build -d
  log "Containers started. To watch logs: $COMPOSE_CMD logs -f"
  exit 0
fi

if [ "$MODE" = "dev" ]; then
  log "Running in Dev mode (non-interactive)"
  # Node (nvm) and pnpm
  if ! command -v node >/dev/null 2>&1 || [ "$(node -v | cut -c2- | cut -d. -f1)" -lt 20 ]; then
    log "Node 20+ not found"
    if [ "$AUTO_INSTALL" = "yes" ]; then
      log "Installing nvm and Node 20"
      # install nvm non-interactively
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
      export NVM_DIR="$HOME/.nvm"
      # shellcheck disable=SC1090
      [ -s "$NVM_DIR/nvm.sh" ] && \ . "$NVM_DIR/nvm.sh"
      nvm install 20
      nvm use 20
    else
      err "Node 20+ missing and AUTO_INSTALL!=yes. Install Node 20 or set AUTO_INSTALL=yes"
      exit 1
    fi
  else
    log "Node present: $(node -v)"
  fi

  if ! command -v pnpm >/dev/null 2>&1; then
    log "pnpm missing — enabling corepack and preparing pnpm"
    corepack enable || true
    corepack prepare pnpm@latest --activate || npm i -g pnpm
  fi
  log "pnpm: $(pnpm -v || echo 'unknown')"

  # Python 3.11 and uv
  if ! command -v python3.11 >/dev/null 2>&1; then
    if [ "$AUTO_INSTALL" = "yes" ]; then
      log "Installing python3.11 via apt"
      apt_install python3.11 python3.11-venv python3.11-distutils || true
    else
      err "python3.11 not found and AUTO_INSTALL!=yes. Install python3.11 or set AUTO_INSTALL=yes"
      exit 1
    fi
  fi

  if ! python3.11 -m pip show uv >/dev/null 2>&1; then
    log "Installing uv via pipx"
    python3.11 -m pip install --user pipx || true
    python3.11 -m pipx ensurepath || true
    python3.11 -m pipx install uv || python3.11 -m pip install --user uv
  fi

  # Install frontend deps
  if [ -d frontend ]; then
    log "Installing frontend deps via pnpm"
    pushd frontend >/dev/null
    pnpm install --frozen-lockfile || pnpm install
    popd >/dev/null
  else
    err "frontend directory not found"
    exit 1
  fi

  # Run dev.sh if exists
  if [ -f dev.sh ]; then
    log "Running ./dev.sh"
    chmod +x dev.sh || true
    ./dev.sh
  else
    err "dev.sh not found — cannot start dev servers automatically"
    exit 1
  fi

  exit 0
fi

err "Unknown MODE: $MODE"
exit 1
