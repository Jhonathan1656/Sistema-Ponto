# Watchdog da stack do ponto. Roda de 5 em 5 min pela Scheduled Task
# "PontoWatchdog".
#
# Existe porque healthcheck do Docker Compose NAO reinicia nada sozinho: ele so
# marca o container como "unhealthy". Sem alguem olhando, um backend travado
# (processo vivo, respondendo erro) fica fora do ar indefinidamente - e o
# restart:always nao ajuda, porque o processo nunca morreu.
#
# Cobre tres falhas:
#   1. engine do Docker caiu  -> religa o Docker Desktop
#   2. container sumiu/parado -> docker compose up -d
#   3. container unhealthy    -> restart daquele servico

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

. "$PSScriptRoot\ops-common.ps1"

try {
    if (-not (Test-DockerEngine)) {
        Write-PontoLog "[watchdog] engine fora do ar; tentando religar."
        if (-not (Wait-DockerEngine -TimeoutMinutes 10)) {
            Write-PontoLog "[watchdog] ERRO: engine nao voltou em 10 min."
            exit 1
        }
    }

    $status = Get-StackStatus

    # Faltando container (ou nenhum): up -d recria o que falta e nao mexe no
    # que ja esta de pe.
    $running = @($status | Where-Object { $_.State -eq "running" })
    if ($running.Count -lt 2) {
        Write-PontoLog "[watchdog] so $($running.Count) container(s) rodando; subindo a stack."
        $res = Invoke-Native { docker compose up -d }
        Write-PontoLog "[watchdog] compose up -d (exit $($res.ExitCode)): $($res.Output)"
        $status = Get-StackStatus
    }

    # Unhealthy: restart:always nao pega esse caso (o processo nunca morreu),
    # entao e aqui que resolve.
    foreach ($c in $status) {
        if ($c.Health -eq "unhealthy") {
            Write-PontoLog "[watchdog] servico '$($c.Service)' unhealthy; reiniciando."
            $svc = $c.Service
            $res = Invoke-Native { docker compose restart $svc }
            Write-PontoLog "[watchdog] restart $svc (exit $($res.ExitCode)): $($res.Output)"
        }
    }

    # Log so quando ha o que contar: rodando a cada 5 min, registrar "tudo ok"
    # encheria o arquivo de ruido e esconderia os eventos que importam.
    if (-not (Test-StackHealthy)) {
        $resumo = ($status | ForEach-Object { "$($_.Service)=$($_.State)/$($_.Health)" }) -join ', '
        Write-PontoLog "[watchdog] stack ainda nao saudavel: $resumo"
    }
    exit 0
}
catch {
    Write-PontoLog "[watchdog] ERRO inesperado: $($_.Exception.Message)"
    exit 1
}
