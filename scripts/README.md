# 脚本工具 — setup-and-run

仓库根目录下新增了两个一键启动/准备脚本，用于简化本地或 Docker 环境下启动项目的流程：

- `scripts/setup-and-run.sh` — 适用于 Linux / macOS 的 Bash 脚本
- `scripts/setup-and-run.ps1` — 适用于 Windows PowerShell 的脚本

这两个脚本的目标：
- 在必要时自动克隆仓库（当指定目录不存在时）
- 在首次运行时复制 `.env.example` -> `.env`（如果 `.env` 不存在）并提示用户编辑
- 提供两种启动模式：Dev 模式（调用仓库内 `dev.sh` / `dev.ps1`，会安装依赖并同时启动前后端）和 Docker 模式（`docker compose up --build`）
- 做基础依赖提示（例如 uv / pnpm / docker / python / node），但不会自动安装系统级工具

使用说明

1) Linux / macOS（Dev 模式，默认）

```bash
# 给脚本可执行权限（仅需一次）
chmod +x scripts/setup-and-run.sh

# 在仓库根目录运行（会调用 ./dev.sh，脚本会安装依赖并同时启动前后端）
./scripts/setup-and-run.sh
```

2) Linux / macOS（Docker 模式）

```bash
# 使用 --docker 参数以 docker compose 启动
./scripts/setup-and-run.sh --docker
```

3) Windows（PowerShell）

在 PowerShell（建议 PowerShell 7+）中运行：

```powershell
# Dev 模式（调用仓库内 dev.ps1）
.\scripts\setup-and-run.ps1

# 或使用 Docker 模式
.\scripts\setup-and-run.ps1 -Docker
```

注意与建议

- 脚本在首次复制 `.env.example` 为 `.env` 后不会自动填入密钥，请务必编辑 `.env` 填入 `TICKFLOW_API_KEY`、`AI_API_KEY` 等必要配置（或在面板 UI 中配置）。
- Dev 模式依赖 `uv`（用于后端依赖管理）和 `pnpm`（前端依赖），若未安装脚本会给出安装建议但不会强制安装。Docker 模式需要已安装并可用的 Docker（Docker Desktop 或 Docker Engine）。
- 若需要，我可以把这段说明也合并到顶层 README.md 的“快速开始”节中，或创建一个 PR 将这些改动放到独立分支以便 review。

文件位置

- https://github.com/ngjan32/tickflow-stock-panel/tree/main/scripts


# Mark executable

要在 Git 中将 `scripts/setup-and-run.sh` 标记为可执行 (git executable bit)，可在本地或 CI 中运行：

```bash
# 在本地检出分支
git fetch origin
git checkout feature/add-setup-scripts

# 设置可执行位并提交
git update-index --chmod=+x scripts/setup-and-run.sh
git commit -m "chore(scripts): mark setup-and-run.sh executable"
git push origin feature/add-setup-scripts
```

我已将上述步骤写入本文件并在 PR 描述中引用，方便合并后维护者一键完成.