# Funcoes compartilhadas pelo autostart e pelo watchdog.
# Dot-source: . "$PSScriptRoot\ops-common.ps1"

$script:PontoLog = "$env:LOCALAPPDATA\ponto-autostart.log"
$script:PontoLogMaxBytes = 2MB

function Write-PontoLog {
    param([Parameter(Mandatory)][string]$Message)

    # Rotaciona pra o log nao crescer sem fim numa maquina que nunca e olhada.
    try {
        $f = Get-Item $script:PontoLog -ErrorAction SilentlyContinue
        if ($f -and $f.Length -gt $script:PontoLogMaxBytes) {
            Move-Item $script:PontoLog "$($script:PontoLog).old" -Force
        }
    } catch { }

    "$(Get-Date -Format o)  $Message" | Out-File $script:PontoLog -Append -Encoding utf8
}

function Invoke-Native {
    <#
      Roda um executavel externo e devolve {ExitCode, Lines, Output}.

      Existe por causa de uma armadilha do PowerShell 5.1: com
      $ErrorActionPreference = "Stop", o "2>&1" de um comando nativo envolve
      cada linha de stderr num ErrorRecord e LANCA excecao - mesmo o programa
      tendo saido com 0. O "docker compose up -d" escreve o progresso
      ("Container X Running") em stderr, entao o watchdog explodia logo depois
      de ter feito o trabalho direito. Aqui a preferencia volta pra Continue
      so durante a chamada, e quem decide o sucesso e o exit code.

      Lines vem separado de Output porque quem faz parse (JSON) precisa das
      linhas intactas - juntar e re-separar por delimitador quebraria se o
      proprio conteudo tivesse esse caractere.
    #>
    param([Parameter(Mandatory)][scriptblock]$Command)

    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $lines = & $Command 2>&1 | ForEach-Object { "$_" }
        $clean = @($lines | Where-Object { $_.Trim() })
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Lines    = $clean
            Output   = ($clean -join ' | ')
        }
    }
    finally {
        $ErrorActionPreference = $prev
    }
}

function Test-DockerEngine {
    # docker info grita no stderr quando o engine esta fora; aqui isso e
    # resposta esperada, nao erro - por isso passa pelo Invoke-Native.
    return (Invoke-Native { docker info --format '{{.ServerVersion}}' }).ExitCode -eq 0
}

function Start-DockerDesktop {
    $exe = "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"
    if (-not (Test-Path $exe)) {
        Write-PontoLog "Docker Desktop nao encontrado em $exe"
        return $false
    }
    if (Get-Process "Docker Desktop" -ErrorAction SilentlyContinue) {
        return $true  # ja esta abrindo; so falta o engine responder
    }
    Write-PontoLog "Iniciando Docker Desktop..."
    Start-Process $exe
    return $true
}

function Wait-DockerEngine {
    param([int]$TimeoutMinutes = 15)

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $launched = $false

    while ((Get-Date) -lt $deadline) {
        if (Test-DockerEngine) {
            Write-PontoLog "Engine do Docker respondendo."
            return $true
        }
        # So tenta lancar uma vez por rodada de espera; o Docker Desktop
        # demora, e abrir varias instancias so atrapalha.
        if (-not $launched) {
            $launched = Start-DockerDesktop
        }
        Start-Sleep -Seconds 10
    }
    return $false
}

function Get-StackStatus {
    # Retorna objetos {Service, State, Health}. Containers parados nao
    # aparecem no "compose ps" - a ausencia e o sinal de que sumiu.
    $res = Invoke-Native { docker compose ps --format json }
    if ($res.ExitCode -ne 0) { return @() }

    # Conforme a versao, o compose devolve um array JSON inteiro ou uma linha
    # por container. Normaliza os dois casos.
    $items = @()
    foreach ($line in $res.Lines) {
        $t = $line.Trim()
        if (-not $t) { continue }
        try { $items += @($t | ConvertFrom-Json) } catch { }
    }

    return $items | ForEach-Object {
        [pscustomobject]@{
            Service = $_.Service
            State   = $_.State
            Health  = $_.Health
        }
    }
}

function Test-StackHealthy {
    $status = Get-StackStatus
    if (-not $status) { return $false }

    foreach ($c in $status) {
        if ($c.State -ne "running") { return $false }
        # Health vazio = container sem healthcheck declarado; "running" basta.
        if ($c.Health -and $c.Health -ne "healthy") { return $false }
    }
    return $true
}

function Wait-StackHealthy {
    param([int]$TimeoutMinutes = 5)

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    while ((Get-Date) -lt $deadline) {
        if (Test-StackHealthy) { return $true }
        Start-Sleep -Seconds 10
    }
    return $false
}
