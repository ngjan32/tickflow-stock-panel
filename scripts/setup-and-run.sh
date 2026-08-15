#!/usr/bin/env bash
# setup-and-run.sh — 一键准备并启动 tickflow-stock-panel (Linux / macOS)
# 用法:
#   ./setup-and-run.sh            # 默认使用 dev 模式（./dev.sh）
#   ./setup-and-run.sh --docker  # 使用 docker compose 启动
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/ngjan32/tickflow-stock-panel.git}"
REPO_DIR="${REPO_DIR:-tickflow-stock-panel}"
USE_DOCKER=0

# parse args
for arg in "$@"; do
  case "$arg" in
    --docker) USE_DOCKER=1 ;;
    --help|-h) echo "Usage: $0 [--docker]"; exit 0 ;;
  esac
done

info(){ echo -e "\033[0;34m[info]\033[0m $*"; }
warn(){ echo -e "\033[0;33m[warn]\033[0m $*"; }
err(){ echo -e "\033[0;31m[err]\033[0m $*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "$1 未安装 — 建议: $2"; exit 1; }
}

version_ge() { # compare simple semver a>=b
  # version_ge 3.11 3.10 -> true
  printf '%s\n%s\n' "$1" "$2" | sort -V -C
}

check_python() {
  if ! command -v python3 >/dev/null 2>&1; then err "python3 未找到, 请安装 Python >= 3.11"; exit 1; fi
  pyv=$(python3 -c 'import sys; v="{}.{}".format(sys.version_info.major, sys.version_info.minor); print(v)')
  if ! version_ge "$pyv" "3.11"; then err "检测到 Python $pyv, 需要 >= 3.11"; exit 1; fi
}

check_node() {
  if ! command -v node >/dev/null 2>&1; then err "node 未找到, 请安装 Node >= 20"; exit 1; fi
  nv=$(node -v | sed 's/^v//')
  major=$(echo "$nv" | cut -d. -f1)
  if [ "$major" -lt 20 ]; then err "检测到 Node $nv, 需要 >=20"; exit 1; fi
}

# Clone repo if missing
if [ ! -d "$REPO_DIR" ]; then
  info "克隆仓库 $REPO_URL -> $REPO_DIR"
  git clone "$REPO_URL" "$REPO_DIR"
fi

cd "$REPO_DIR"

# Ensure .env
if [ ! -f .env ]; then
  if [ -f .env.example ]; then
    cp .env.example .env
    warn "已复制 .env.example -> .env，请编辑 .env 填入 TICKFLOW_API_KEY / AI_API_KEY 等（如需要）"
  else
    warn "仓库中未找到 .env.example，请手动创建 .env"
  fi
fi

if [ "$USE_DOCKER" -eq 1 ]; then
  # Docker path
  require_cmd docker "https://docs.docker.com/get-docker/"
  # docker compose v2 uses `docker compose`
  if command -v docker-compose >/dev/null 2>&1; then
    info "使用 docker-compose 启动 (docker-compose)"
    docker-compose up --build
  else
    info "使用 docker compose 启动 (docker compose)"
    docker compose up --build
  fi
  exit 0
fi

# Dev mode path: ensure uv & pnpm
if command -v uv >/dev/null 2>&1; then
  info "检测到 uv"
else
  warn "未检测到 uv。可用: curl -LsSf https://astral.sh/uv/install.sh | sh"
fi
if command -v pnpm >/dev/null 2>&1; then
  info "检测到 pnpm"
else
  warn "未检测到 pnpm。可用: npm i -g pnpm 或 corepack enable && corepack prepare pnpm@9 --activate"
fi

# Check Python/Node versions (warn but allow)
if command -v python3 >/dev/null 2>&1; then
  pyv=$(python3 -c 'import sys; print("{}.{}".format(sys.version_info.major, sys.version_info.minor))')
  info "检测到 Python $pyv"
else
  warn "未检测到 python3"
fi
if command -v node >/dev/null 2>&1; then
  nv=$(node -v)
  info "检测到 Node $nv"
else
  warn "未检测到 node"
fi

info "开始用仓库内 dev.sh 启动（脚本会安装依赖并同时启动前后端）"
if [ ! -x ./dev.sh ]; then
  chmod +x ./dev.sh || true
fi
./dev.sh
