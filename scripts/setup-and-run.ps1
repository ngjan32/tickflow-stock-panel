<#
setup-and-run.ps1 — 一键准备并启动 tickflow-stock-panel (Windows PowerShell)
用法:
  .\setup-and-run.ps1           # 默认使用 dev 模式 (\.\dev.ps1)
  .\setup-and-run.ps1 -Docker  # 使用 Docker Compose 启动
#>
param(
  [string]$RepoUrl = "https://github.com/ngjan32/tickflow-stock-panel.git",
  [string]$RepoDir = "tickflow-stock-panel",
  [switch]$Docker
)

function Info($m){ Write-Host "[info] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[warn] $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "[err] $m" -ForegroundColor Red }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Err "git 未安装或不可用，请先安装 Git: https://git-scm.com/"
  exit 1
}

if (-not (Test-Path -Path $RepoDir)) {
  Info "克隆仓库 $RepoUrl -> $RepoDir"
  git clone $RepoUrl $RepoDir
}

Set-Location $RepoDir

if (-not (Test-Path -Path .env)) {
  if (Test-Path .env.example) {
    Copy-Item .env.example .env -Force
    Warn "已复制 .env.example -> .env，请编辑 .env 填入 TICKFLOW_API_KEY / AI_API_KEY 等（如需要）"
  } else {
    Warn "未找到 .env.example，请手动创建 .env"
  }
}

if ($Docker) {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Err "docker 未安装，请先安装 Docker Desktop"
    exit 1
  }
  Info "使用 Docker Compose 启动"
  # 使用 docker compose 或 docker-compose
  if (Get-Command docker-compose -ErrorAction SilentlyContinue) {
    docker-compose up --build
  } else {
    docker compose up --build
  }
  exit 0
}

# Dev 模式: 在 Windows 上仓库包含 dev.ps1
if (-not (Get-Command pwsh -ErrorAction SilentlyContinue) -and $PSVersionTable.PSVersion.Major -lt 7) {
  Warn "建议使用 PowerShell 7+ (pwsh) 以获得最佳兼容性"
}

if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
  Warn "未检测到 pnpm，安装建议: npm i -g pnpm 或使用 corepack"
}

if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
  Warn "未检测到 uv（用于管理后端虚拟环境/依赖），可用: Invoke-WebRequest -UseBasicParsing https://astral.sh/uv/install.ps1 | iex"
}

# Run dev.ps1
if (Test-Path .\dev.ps1) {
  Info "运行 .\\dev.ps1 启动前后端（PowerShell）"
  # 使用当前 PowerShell 执行脚本，保留控制台输出
  & .\dev.ps1
} else {
  Err "未找到仓库内 dev.ps1，请手动启动或使用 Docker"
  exit 1
}
