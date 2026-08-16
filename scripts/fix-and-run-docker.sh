#!/usr/bin/env bash
# scripts/fix-and-run-docker.sh
# 一键修复常见 Docker/socket/permission 问题并在项目目录启动 docker compose
# 用法:
#   ./scripts/fix-and-run-docker.sh [PROJECT_DIR]
# 或
#   PROJECT_DIR=/path/to/project ./scripts/fix-and-run-docker.sh

set -euo pipefail
IFS=$'\n\t'

PROVIDED_DIR="${1:-}" 
PROJECT_DIR="${PROJECT_DIR:-$PROVIDED_DIR}"
# 使用 sudo 运行脚本时，SUDO_USER 保存真实用户名；否则使用当前 $USER
TARGET_USER="${SUDO_USER:-${USER:-}}"

log() { echo "[fix] $*"; }
err() { echo "[fix][ERROR] $*" >&2; }

# Helper: find first compose file under candidate roots
find_compose_dir() {
  local roots=("." "$HOME")
  for r in "${roots[@]}"; do
    if [ -d "$r" ]; then
      local path
      path=$(find "$r" -maxdepth 4 -type f \( -name 'docker-compose.yml' -o -name 'docker-compose.yaml' -o -name 'compose.yaml' -o -name 'docker-compose.*.y*ml' \) -print -quit 2>/dev/null || true)
      if [ -n "$path" ]; then
        dirname "$path"
        return 0
      fi
    fi
  done
  return 1
}

# 1) Determine project dir
if [ -z "$PROJECT_DIR" ]; then
  log "No PROJECT_DIR given — searching for docker-compose.yml under current dir and $HOME (depth 4)"
  PROJECT_DIR=$(find_compose_dir || true) || true
fi

if [ -z "$PROJECT_DIR" ]; then
  err "未提供项目路径且未在当前目录或 $HOME 下找到 docker-compose.yml。请作为第一个参数传入项目路径或设置 PROJECT_DIR 环境变量。"
  err "示例： PROJECT_DIR=/home/you/tickflow-stock-panel/tickflow-stock-panel/tickflow-stock-panel ./scripts/fix-and-run-docker.sh"
  exit 1
fi

# Canonicalize
PROJECT_DIR=$(realpath "$PROJECT_DIR")
log "使用项目目录: $PROJECT_DIR"

# 2) Ensure docker group exists
if ! getent group docker >/dev/null 2>&1; then
  log "docker 组不存在，创建 docker 组（需要 sudo）"
  sudo groupadd docker || true
else
  log "docker 组已存在"
fi

# 3) Add user to docker group
if [ -z "$TARGET_USER" ]; then
  err "无法确定要加入 docker 组的用户（SUDO_USER 或 USER 未设置）"
else
  log "将用户 $TARGET_USER 加入 docker 组（需要 sudo）"
  sudo usermod -aG docker "$TARGET_USER" || true
fi

# 4) Reload systemd
log "重新加载 systemd 单元配置"
sudo systemctl daemon-reload || true

# 5) Start containerd (依赖项)
log "启动并启用 containerd"
if ! sudo systemctl enable --now containerd; then
  err "containerd 启动失败。查看日志: sudo journalctl -u containerd -n 200 --no-pager"
  sudo journalctl -u containerd -n 200 --no-pager || true
  exit 1
fi
sudo systemctl status containerd --no-pager -l || true

# 6) Enable and start docker.socket
log "启用并启动 docker.socket"
if ! sudo systemctl enable --now docker.socket; then
  err "docker.socket 启动失败。通常表示 Group=docker 未解析或权限问题。请确保 docker 组存在并重试。"
  sudo systemctl status docker.socket --no-pager -l || true
  sudo journalctl -u docker.socket -n 200 --no-pager || true
  exit 1
fi
sudo systemctl status docker.socket --no-pager -l || true

# 7) Start docker service
log "启用并启动 docker.service"
if ! sudo systemctl enable --now docker; then
  err "docker.service 启动失败。查看 journal： sudo journalctl -u docker -n 200 --no-pager"
  sudo systemctl status docker --no-pager -l || true
  sudo journalctl -u docker -n 200 --no-pager || true
  exit 1
fi
sudo systemctl status docker --no-pager -l || true

# 8) Verify docker daemon
log "验证 Docker 守护进程可用性"
if ! docker info >/dev/null 2>&1; then
  err "docker 命令无法访问守护进程。可能需要重新登录以使 docker 组修改生效，或 docker 服务未正确启动。"
  echo "输出:"
  docker info || true
  err "请尝试退出并重新登录 shell，然后再运行本脚本，或继续用 sudo 启动 compose（脚本后面会尝试自动回退到 sudo）。"
fi

# 9) Start compose in project dir
cd "$PROJECT_DIR"
log "进入 $PROJECT_DIR，寻找 compose 文件"
COMPOSE_FILE=""
for f in docker-compose.yml docker-compose.yaml compose.yaml docker-compose.yml; do
  if [ -f "$f" ]; then
    COMPOSE_FILE="$f"
    break
  fi
done
if [ -z "$COMPOSE_FILE" ]; then
  # try find
  COMPOSE_FILE=$(find . -maxdepth 2 -type f -name 'docker-compose*.y*ml' -print -quit 2>/dev/null || true)
  if [ -n "$COMPOSE_FILE" ]; then
    COMPOSE_FILE="$(realpath "$COMPOSE_FILE")"
  fi
fi

if [ -z "$COMPOSE_FILE" ]; then
  err "在 $PROJECT_DIR 未找到 docker-compose 文件。"
  exit 1
fi
log "使用 Compose 文件: $COMPOSE_FILE"

# Try to run compose without sudo first; if permission denied, retry with sudo
run_compose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose -f "$COMPOSE_FILE" up --build -d
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose -f "$COMPOSE_FILE" up --build -d
  else
    err "未检测到 docker compose 可用命令，请安装 docker compose 或 docker-compose 二进制。"
    exit 1
  fi
}

log "尝试以当前用户启动 compose（若权限不足脚本会回退到 sudo）"
if run_compose; then
  log "Compose 已启动 (当前用户)。"
else
  log "当前用户启动失败，尝试使用 sudo 启动 compose"
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    sudo docker compose -f "$COMPOSE_FILE" up --build -d
  else
    sudo docker-compose -f "$COMPOSE_FILE" up --build -d
  fi
fi

log "显示最新的 200 行 compose 日志："
if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose -f "$COMPOSE_FILE" logs --no-color --tail=200 || true
else
  docker-compose -f "$COMPOSE_FILE" logs --no-color --tail=200 || true
fi

log "完成。注意：为了在不使用 sudo 的情况下使用 docker，你可能需要登出并重新登录（或重启你的 shell 会话）以使 docker 组更改生效。"
