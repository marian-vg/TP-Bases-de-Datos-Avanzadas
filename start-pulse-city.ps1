param(
    [switch]$NoBuild,
    [switch]$NoOpenBrowser
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$gameRoot = Join-Path $repoRoot "pulse-city-game"
$frontendUrl = "http://localhost:5173"
$backendHealthUrl = "http://localhost:8000/api/v1/health"
$dbContainerName = "bd_smartcity_tp"

function Write-Step([string]$message) {
    Write-Host ""
    Write-Host "==> $message" -ForegroundColor Cyan
}

function Test-CommandExists([string]$name) {
    return $null -ne (Get-Command $name -ErrorAction SilentlyContinue)
}

function Wait-ForContainerHealth([string]$containerName, [int]$timeoutSeconds = 90) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $status = docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $containerName 2>$null
        $status = ($status | Out-String).Trim()

        if ($status -eq "healthy" -or $status -eq "running") {
            return
        }

        Start-Sleep -Seconds 2
    }

    throw "El contenedor '$containerName' no quedo listo dentro de ${timeoutSeconds}s."
}

function Wait-ForHttpOk([string]$url, [int]$timeoutSeconds = 90) {
    $deadline = (Get-Date).AddSeconds($timeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        try {
            $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 10
            if ($response.StatusCode -ge 200 -and $response.StatusCode -lt 300) {
                return
            }
        } catch {
        }

        Start-Sleep -Seconds 2
    }

    throw "La URL '$url' no respondio OK dentro de ${timeoutSeconds}s."
}

if (-not (Test-CommandExists "docker")) {
    throw "Docker no esta instalado o no esta en PATH."
}

Write-Step "Verificando Docker"
docker info | Out-Null

Write-Step "Levantando la base canonica del TP"
Push-Location $repoRoot
try {
    docker compose up -d
} finally {
    Pop-Location
}

Write-Step "Esperando que PostgreSQL quede listo"
Wait-ForContainerHealth -containerName $dbContainerName

Write-Step "Levantando Pulse City"
Push-Location $gameRoot
try {
    if ($NoBuild) {
        docker compose up -d
    } else {
        docker compose up -d --build
    }
} finally {
    Pop-Location
}

Write-Step "Esperando que backend y frontend respondan"
Wait-ForHttpOk -url $backendHealthUrl
Wait-ForHttpOk -url $frontendUrl

Write-Host ""
Write-Host "Pulse City esta listo." -ForegroundColor Green
Write-Host "Frontend: $frontendUrl"
Write-Host "Backend:  $backendHealthUrl"

if (-not $NoOpenBrowser) {
    Write-Step "Abriendo el juego en el navegador"
    Start-Process $frontendUrl | Out-Null
}
