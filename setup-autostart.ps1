# Instala a recuperacao automatica pos-queda de energia. Rodar UMA VEZ,
# como administrador:
#
#   powershell -ExecutionPolicy Bypass -File .\setup-autostart.ps1
#
# O que faz:
#   1. Scheduled Task "PontoAutostart"  - sobe a stack no logon, com retry
#   2. Scheduled Task "PontoWatchdog"   - vigia a stack a cada 5 min
#   3. Remove o atalho antigo da pasta Startup (virou task)
#   4. Desliga o Fast Startup do Windows
#   5. Garante que o Docker Desktop inicie no logon
#
# O que NAO faz (e voce precisa fazer a mao): configurar a BIOS pra religar
# quando a energia volta. Sem isso, nada aqui roda. Ver docs/RECOVERY.md.

$ErrorActionPreference = "Stop"

$isAdmin = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "ERRO: rode este script como administrador." -ForegroundColor Red
    exit 1
}

$root = $PSScriptRoot
$me   = "$env:USERDOMAIN\$env:USERNAME"

function New-PontoTask {
    param($Name, $Script, $Trigger, $Description)

    $action = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$root\$Script`"" `
        -WorkingDirectory $root

    # Interactive: o Docker Desktop precisa de sessao de usuario, entao a task
    # NAO pode rodar como servico/SYSTEM.
    $principal = New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RestartCount 3 `
        -RestartInterval (New-TimeSpan -Minutes 5) `
        -ExecutionTimeLimit (New-TimeSpan -Hours 1)

    Unregister-ScheduledTask -TaskName $Name -Confirm:$false -ErrorAction SilentlyContinue

    Register-ScheduledTask `
        -TaskName $Name `
        -Action $action `
        -Trigger $Trigger `
        -Principal $principal `
        -Settings $settings `
        -Description $Description | Out-Null

    Write-Host "  [ok] task '$Name' registrada" -ForegroundColor Green
}

Write-Host "`n1) Registrando tarefas agendadas..." -ForegroundColor Cyan

# 30s de folga: da tempo do Docker Desktop comecar a subir junto com o logon.
$bootTrigger = New-ScheduledTaskTrigger -AtLogOn -User $me
$bootTrigger.Delay = "PT30S"

New-PontoTask -Name "PontoAutostart" -Script "autostart-windows.ps1" `
    -Trigger $bootTrigger `
    -Description "Sobe a stack do ponto apos o logon (recuperacao pos-queda de energia)."

$wdTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(5) `
    -RepetitionInterval (New-TimeSpan -Minutes 5)
try {
    $wdTrigger.Repetition.Duration = ""   # "" = indefinidamente
} catch { }

New-PontoTask -Name "PontoWatchdog" -Script "watchdog-windows.ps1" `
    -Trigger $wdTrigger `
    -Description "Vigia a stack do ponto e reinicia containers travados/unhealthy."

Write-Host "`n2) Removendo atalho antigo da pasta Startup..." -ForegroundColor Cyan
$old = "$([Environment]::GetFolderPath('Startup'))\ponto-autostart.cmd"
if (Test-Path $old) {
    Remove-Item $old -Force
    Write-Host "  [ok] removido (a task substitui, com retry e log)" -ForegroundColor Green
} else {
    Write-Host "  [--] ja nao existia" -ForegroundColor DarkGray
}

Write-Host "`n3) Desligando Fast Startup..." -ForegroundColor Cyan
# Fast Startup faz o "desligar" virar hibernacao parcial. Num servidor que
# precisa voltar limpo depois de um corte de energia isso atrapalha: o estado
# salvo pode ficar inconsistente e o WSL2/Docker sobe quebrado.
Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" `
    -Name "HiberbootEnabled" -Value 0 -Type DWord
Write-Host "  [ok] HiberbootEnabled = 0" -ForegroundColor Green

Write-Host "`n4) Garantindo autostart do Docker Desktop..." -ForegroundColor Cyan
$run = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
Set-ItemProperty -Path $run -Name "Docker Desktop" `
    -Value "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe"

# StartupApproved guarda o "desativado no Gerenciador de Tarefas"; 02 = ativado.
$approved = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run"
if (Test-Path $approved) {
    $enabled = [byte[]](2,0,0,0,0,0,0,0,0,0,0,0)
    Set-ItemProperty -Path $approved -Name "Docker Desktop" -Value $enabled
}

$settingsFile = "$env:APPDATA\Docker\settings-store.json"
if (Test-Path $settingsFile) {
    $json = Get-Content $settingsFile -Raw | ConvertFrom-Json
    $json.AutoStart = $true
    $json | ConvertTo-Json -Depth 20 | Out-File $settingsFile -Encoding utf8
    Write-Host "  [ok] AutoStart = true no settings-store.json" -ForegroundColor Green
}
Write-Host "  [ok] chave Run apontando pro Docker Desktop" -ForegroundColor Green

Write-Host "`nPronto." -ForegroundColor Green
Write-Host "FALTA VOCE FAZER: BIOS -> 'Restore on AC Power Loss' = Power On." -ForegroundColor Yellow
Write-Host "Sem isso o PC nao liga sozinho e nada disso roda. Ver docs/RECOVERY.md`n" -ForegroundColor Yellow
