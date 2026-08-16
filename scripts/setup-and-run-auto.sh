#!/usr/bin/env bash
# setup-and-run-auto.sh
# One-shot helper to prepare and run tickflow-stock-panel on Linux.
# Usage: ./scripts/setup-and-run-auto.sh
set -euo pipefail
IFS=$'\n\t'

REPO_URL="https://github.com/ngjan32/tickflow-stock-panel.git"
REPO_DIR="tickflow-stock-panel"

confirm() {
  # $1 = prompt, default No
  read -r -p "$1 [y/N]: " ans
  case "$ans" in
    [Yy]|[Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
  esac
}

echo "=== TickFlow Stock Panel — one-shot setup & run helper ==="
echo

# 1) Clone or update repo
if [ -d "$REPO_DIR/.git" ]; then
  echo "Repository exists. Pulling latest changes..."
  cd "$REPO_DIR"
  git fetch --all --prune
  git pull --ff-only || true
else
  echo "Cloning repository..."
  git clone "$REPO_URL" "$REPO_DIR"
  cd "$REPO_DIR"
fi

# 2) Ensure scripts directory present
mkdir -p scripts

# 3) Prepare .env
if [ ! -f ".env" ]; then
  echo "Creating .env from .env.example..."
  if [ -f .env.example ]; then
    cp .env.example .env
    echo ".env created from .env.example."
    echo "Please edit .env to provide TICKFLOW_API_KEY (and AI_API_KEY if you want AI)."
    if confirm "Open .env in nano now to edit?"; then
      command -v nano >/dev/null 2>&1 && nano .env || ${EDITOR:-vi} .env
    else
      echo "Remember to edit .env before using AI features or provider keys."
    fi
  else
    echo "Warning: .env.example not found. Creating minimal .env."
    cat > .env <<'EOF'
TICKFLOW_API_KEY=
AI_PROVIDER=openai_compat
AI_BASE_URL=https://api.deepseek.com/v1
AI_API_KEY=
AI_MODEL=deepseek-chat
PORT=3018
DATA_DIR=./data
EOF
    echo ".env created; you should edit it."
  fi
else
  echo ".env already exists — skipping creation."
fi

# 4) Choose mode
echo
echo "Choose run mode:"
echo "  1) Docker (recommended, minimal host deps)"
echo "  2) Dev (for development: requires Node, pnpm, Python 3.11, uv)"
read -r -p "Enter 1 or 2 (default 1): " mode
mode=${mode:-1}

# Helper checks
has_cmd() { command -v "$1" >/dev/null 2>&1; }

install_docker_if_missing() {
  if has_cmd docker; then
    echo "Docker found."
    return 0
  fi
  echo "Docker not found."
  if confirm "Install Docker using get-docker.sh (requires sudo)?"; then
    curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
    sudo sh /tmp/get-docker.sh
    rm -f /tmp/get-docker.sh
    echo "Docker installed. Adding $USER to docker group (requires re-login to take effect)."
    sudo usermod -aG docker "$USER" || true
    echo "If you just added your user to docker group, you may need to log out and in again."
  else
    echo "Skipping Docker install. You must install Docker manually to use Docker mode."
    exit 1
  fi
}

# 5A) Docker mode
if [ "$mode" = "1" ] || [ "$mode" = "docker" ]; then
  echo
  echo "=== Docker mode selected ==="
  install_docker_if_missing

  # Check for docker-compose (modern Docker includes compose plugin)
  if ! docker compose version >/dev/null 2>&1; then
    echo "docker compose not available as 'docker compose'. Checking 'docker-compose'..."
    if has_cmd docker-compose; then
      echo "'docker-compose' binary found and will be used."
      COMPOSE_CMD="docker-compose"
    else
      echo "docker compose plugin or docker-compose not found."
      if confirm "Install docker-compose (v2 plugin or separate) via apt (may require manual steps)?"; then
        sudo apt update
        sudo apt install -y docker-compose-plugin || true
      fi
      # final check
      if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
      elif has_cmd docker-compose; then
        COMPOSE_CMD="docker-compose"
      else
        echo "docker compose still unavailable. Please install docker compose plugin or docker-compose."
        exit 1
      fi
    fi
  else
    COMPOSE_CMD="docker compose"
  fi

  # Optional CODEX mounting hint
  if ! grep -q '^CODEX_HOME_HOST=' .env 2>/dev/null; then
    echo
    echo "If you want container to access local Codex login, set CODEX_HOME_HOST in .env to your ~/.codex path."
  fi

  echo "Starting services with: $COMPOSE_CMD up --build -d"
  $COMPOSE_CMD up --build -d

  echo
  echo "Waiting a few seconds for containers to initialize..."
  sleep 5
  echo "Tailing compose logs. Press Ctrl-C to detach (containers keep running)."
  $COMPOSE_CMD logs -f

  exit 0
fi

# 5B) Dev mode
if [ "$mode" = "2" ] || [ "$mode" = "dev" ]; then
  echo
  echo "=== Dev mode selected ==="

  # Node + pnpm
  if ! has_cmd node || [ "$(node -v | cut -c2- | cut -d. -f1)" -lt 20 ]; then
    echo "Node 20+ not found."
    if confirm "Install Node 20 via nvm (requires curl)?"; then
      if ! has_cmd curl; then
        sudo apt update && sudo apt install -y curl
      fi
      curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash
      export NVM_DIR="$HOME/.nvm"
      # shellcheck disable=SC1090
      [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
      nvm install 20
      nvm use 20
    else
      echo "Please install Node 20+ and rerun."
      exit 1
    fi
  else
    echo "Node found: $(node -v)"
  fi

  if ! has_cmd pnpm; then
    echo "pnpm not found. Installing via corepack..."
    corepack enable || true
    corepack prepare pnpm@latest --activate || npm i -g pnpm
  fi
  echo "pnpm: $(pnpm -v || true)"

  # Python 3.11 + uv
  if ! python3.11 -V >/dev/null 2>&1; then
    echo "Python 3.11 was not found."
    if confirm "Attempt to install python3.11 via apt (may not be available on all distros)?"; then
      sudo apt update
      sudo apt install -y python3.11 python3.11-venv python3.11-distutils || true
    else
      echo "Please install Python 3.11 and rerun."
      exit 1
    fi
  fi
  if ! python3.11 -m pip show uv >/dev/null 2>&1; then
    echo "uv not installed. Installing uv (pipx recommended)..."
    python3.11 -m pip install --user pipx || true
    python3.11 -m pipx ensurepath || true
    python3.11 -m pipx install uv || python3.11 -m pip install --user uv
  fi

  # Install frontend deps and backend deps via project scripts
  echo
  echo "Installing frontend dependencies..."
  if [ -d frontend ]; then
    pushd frontend >/dev/null
    pnpm install --frozen-lockfile || pnpm install
    popd >/dev/null
  else
    echo "Warning: frontend directory not found."
  fi

  echo "Preparing backend..."
  if [ -f dev.sh ]; then
    echo "Running ./dev.sh to build and start backend+frontend (this may install more deps)..."
    chmod +x dev.sh || true
    ./dev.sh
  else
    echo "dev.sh not found; try starting backend manually per README."
  fi

  exit 0
fi

echo "Invalid mode. Exiting."
exit 1
