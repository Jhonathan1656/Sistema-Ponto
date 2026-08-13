# Diagnostico pos-boot: a stack voltou sozinha? Em quanto tempo?
# Rode depois de um teste de queda de energia / reinicio.
#
#   powershell -ExecutionPolicy Bypass -File .\check-recovery.ps1

Set-Location $PSScriptRoot
. "$PSScriptRoot\ops-common.ps1"

$boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
$agora = Get-Date

Write-Host ""
Write-Host "=== BOOT ===" -ForegroundColor Cyan
Write-Host "  Ligou em : $boot"
Write-Host "  Uptime   : $([int]($agora - $boot).TotalMinutes) min"

Write-Host ""
Write-Host "=== TAREFAS AGENDADAS ===" -ForegroundColor Cyan
foreach ($n in @('PontoAutostart','PontoWatchdog')) {
    $i = Get-ScheduledTaskInfo -TaskName $n -ErrorAction SilentlyContinue
    if (-not $i) {
        Write-Host "  $n : NAO REGISTRADA - rode setup-autostart.ps1 como admin" -ForegroundColor Red
        continue
    }
    # So conta se rodou DEPOIS do boot; senao e execucao velha de antes.
    $posBoot = $i.LastRunTime -gt $boot
    $cor = if ($i.LastTaskResult -eq 0 -and $posBoot) { "Green" } else { "Yellow" }
    $delta = if ($posBoot) { "+$([int]($i.LastRunTime - $boot).TotalSeconds)s apos o boot" } else { "ANTES do boot (nao rodou nesta sessao)" }
    Write-Host "  $n : resultado=$($i.LastTaskResult) | $delta" -ForegroundColor $cor
}

Write-Host ""
Write-Host "=== CONTAINERS ===" -ForegroundColor Cyan
if (-not (Test-DockerEngine)) {
    Write-Host "  engine do Docker FORA DO AR" -ForegroundColor Red
} else {
    foreach ($c in Get-StackStatus) {
        $cor = if ($c.State -eq 'running' -and $c.Health -ne 'unhealthy') { "Green" } else { "Red" }
        Write-Host "  $($c.Service) : $($c.State)/$($c.Health)" -ForegroundColor $cor
    }
}

Write-Host ""
Write-Host "=== ENDPOINTS ===" -ForegroundColor Cyan
foreach ($alvo in @(@{n='API     ';u='http://127.0.0.1:8000/health'}, @{n='Frontend';u='http://127.0.0.1:8080/'})) {
    try {
        # HttpWebRequest em vez de Invoke-WebRequest porque precisamos NAO
        # seguir o redirect e mesmo assim ler o status: o 302 do gate de acesso
        # perde a porta :8080 e aponta pra porta 80, onde nao ha nada. No PS 5.1
        # o -MaximumRedirection 0 lanca InvalidOperationException sem expor a
        # Response, entao nao da pra ler o codigo por ali.
        $req = [System.Net.HttpWebRequest]::Create($alvo.u)
        $req.AllowAutoRedirect = $false
        $req.Timeout = 15000
        $req.Proxy = $null
        try {
            $resp = $req.GetResponse()
            $code = [int]$resp.StatusCode
            $resp.Close()
        } catch [System.Net.WebException] {
            if (-not $_.Exception.Response) { throw }
            $code = [int]$_.Exception.Response.StatusCode
        }
        # 3xx conta como sucesso: prova que o nginx esta servindo e o gate
        # respondeu. Quem valida o destino do redirect e o navegador.
        $cor = if ($code -lt 400) { "Green" } else { "Red" }
        Write-Host "  $($alvo.n) : HTTP $code" -ForegroundColor $cor
    } catch {
        Write-Host "  $($alvo.n) : FALHOU - $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== TUNEL CLOUDFLARE ===" -ForegroundColor Cyan
# Os usuarios chegam por https://ponto.vmacengenharia.com via Cloudflare
# Tunnel. Checar so o localhost daria tudo verde com o tunel fora do ar e o
# site devolvendo erro 1033 pra todo mundo - falso positivo.
$svc = Get-Service Cloudflared -ErrorAction SilentlyContinue
if (-not $svc) {
    Write-Host "  servico : NAO ENCONTRADO" -ForegroundColor Yellow
} else {
    $cor = if ($svc.Status -eq 'Running') { "Green" } else { "Red" }
    Write-Host "  servico : $($svc.Status) / $($svc.StartType)" -ForegroundColor $cor
}

$pub = 'https://ponto.vmacengenharia.com/'
try {
    # PS 5.1 negocia TLS 1.0 por padrao; a Cloudflare recusa.
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $req = [System.Net.HttpWebRequest]::Create($pub)
    $req.AllowAutoRedirect = $false
    $req.Timeout = 25000
    try {
        $resp = $req.GetResponse()
        $code = [int]$resp.StatusCode
        $resp.Close()
    } catch [System.Net.WebException] {
        if (-not $_.Exception.Response) { throw }
        $code = [int]$_.Exception.Response.StatusCode
    }
    # 3xx e sucesso: e o redirect do gate de acesso.
    $cor = if ($code -lt 400) { "Green" } else { "Red" }
    Write-Host "  publico : HTTP $code  ($pub)" -ForegroundColor $cor
} catch {
    Write-Host "  publico : FALHOU - $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "            (usuarios veem erro 1033 da Cloudflare)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== TEMPO DE RECUPERACAO ===" -ForegroundColor Cyan
$linha = Select-String -Path $script:PontoLog -Pattern "OK: stack no ar e saudavel" -ErrorAction SilentlyContinue | Select-Object -Last 1
if ($linha -and $linha.Line -match '^(\S+)\s') {
    $quando = [datetime]::Parse($matches[1])
    if ($quando -gt $boot) {
        Write-Host "  Stack saudavel $([int]($quando - $boot).TotalSeconds)s apos o boot" -ForegroundColor Green
    } else {
        Write-Host "  Ultimo 'stack saudavel' e anterior ao boot atual." -ForegroundColor Yellow
    }
} else {
    Write-Host "  Nenhum registro de sucesso no log ainda." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== ULTIMAS LINHAS DO LOG ===" -ForegroundColor Cyan
Get-Content $script:PontoLog -Tail 8 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
Write-Host ""
