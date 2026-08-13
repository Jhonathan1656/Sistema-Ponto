# Sobe a stack do ponto depois do boot, sem depender de ninguem clicar em nada.
#
# Cenario alvo: queda/pico de energia. A BIOS religa o PC, o Windows faz
# autologon, e este script garante que Docker Desktop + containers voltem.
#
# Diferenca pro que existia antes:
#   - inicia o Docker Desktop se ele nao subiu (antes so esperava);
#   - espera 15 min em vez de 6 (boot pos-queda e lento: disco frio, WSL2,
#     chkdsk eventual);
#   - confere se a stack ficou saudavel de verdade, nao so se o comando saiu 0.
#
# Chamado pela Scheduled Task "PontoAutostart" (ver setup-autostart.ps1).

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

. "$PSScriptRoot\ops-common.ps1"

Write-PontoLog "--- autostart iniciando (usuario: $env:USERNAME) ---"

try {
    if (-not (Wait-DockerEngine -TimeoutMinutes 15)) {
        Write-PontoLog "ERRO: engine do Docker nao respondeu em 15 min; abortando."
        exit 1
    }

    # up -d e idempotente: recria so o que estiver faltando.
    $res = Invoke-Native { docker compose up -d }
    Write-PontoLog "docker compose up -d (exit $($res.ExitCode)): $($res.Output)"

    if ($res.ExitCode -ne 0) {
        Write-PontoLog "ERRO: compose up falhou."
        exit 1
    }

    if (Wait-StackHealthy -TimeoutMinutes 5) {
        Write-PontoLog "OK: stack no ar e saudavel."
        exit 0
    }

    Write-PontoLog "AVISO: stack subiu mas nao ficou healthy em 5 min. O watchdog assume daqui."
    exit 1
}
catch {
    Write-PontoLog "ERRO inesperado: $($_.Exception.Message)"
    exit 1
}
