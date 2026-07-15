$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$gameRoot = Join-Path $repoRoot "smart-city-game"

function Write-Step([string]$message) {
    Write-Host ""
    Write-Host "==> $message" -ForegroundColor Cyan
}

Write-Step "Apagando Smart City (Frontend & Backend)..."
Push-Location $gameRoot
try {
    docker compose down
} finally {
    Pop-Location
}

Write-Step "Apagando base canonica del TP (PostgreSQL)..."
Push-Location $repoRoot
try {
    docker compose down
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Entornos detenidos con exito." -ForegroundColor Green
