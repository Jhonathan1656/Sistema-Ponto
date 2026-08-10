# Sobe a stack do ponto no logon, depois que o Docker Desktop fica pronto.
# Reforco do restart:unless-stopped: cobre o caso de container parado manual.
# Chamado pela pasta Startup do usuario (ver instrucoes no fim do arquivo).

$ErrorActionPreference = "SilentlyContinue"
$log = "$env:LOCALAPPDATA\ponto-autostart.log"
"$(Get-Date -Format o)  --- autostart iniciando ---" | Out-File $log -Append

# Espera o engine do Docker responder (Docker Desktop leva ~1-2 min no boot).
$deadline = (Get-Date).AddMinutes(6)
$ready = $false
while ((Get-Date) -lt $deadline) {
    docker info *> $null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 10
}

if (-not $ready) {
    "$(Get-Date -Format o)  Docker nao ficou pronto em 6 min; abortando." | Out-File $log -Append
    exit 1
}

Set-Location $PSScriptRoot
docker compose up -d *>> $log
"$(Get-Date -Format o)  docker compose up -d (exit $LASTEXITCODE)" | Out-File $log -Append
