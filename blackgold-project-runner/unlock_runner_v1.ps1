$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$LockPath = Join-Path $Base 'runner.lock'
$PulseTask = 'BlackGold_Project_Runner_Pulse_V1'
$OldWatchdogTask = 'BlackGold_Project_Runner_Watchdog_V1'

if (-not (Test-Path -LiteralPath $RunnerPath)) { throw "Runner nao encontrado: $RunnerPath" }

Write-Host '[1/4] Parando apenas processos antigos do BlackGold Project Runner...' -ForegroundColor Cyan
$patterns = @([regex]::Escape($RunnerPath), [regex]::Escape((Join-Path $Base 'watchdog.ps1')))
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessId -ne $PID -and $_.CommandLine -and (
        $_.CommandLine -match $patterns[0] -or $_.CommandLine -match $patterns[1]
    )
})
foreach ($p in $procs) {
    Write-Host ("Encerrando PID " + $p.ProcessId) -ForegroundColor DarkYellow
    Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
}

Write-Host '[2/4] Limpando lock antigo...' -ForegroundColor Cyan
Remove-Item -LiteralPath $LockPath -Force -ErrorAction SilentlyContinue

Write-Host '[3/4] Validando Runner...' -ForegroundColor Cyan
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($RunnerPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) { throw ('Runner invalido: ' + (($errors | ForEach-Object {$_.Message}) -join ' | ')) }

Write-Host '[4/4] Executando rodada limpa...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if ($LASTEXITCODE -ne 0) { throw "Runner terminou com codigo $LASTEXITCODE" }

Import-Module ScheduledTasks -ErrorAction SilentlyContinue
Enable-ScheduledTask -TaskName $PulseTask -ErrorAction SilentlyContinue | Out-Null
Unregister-ScheduledTask -TaskName $OldWatchdogTask -Confirm:$false -ErrorAction SilentlyContinue

Write-Host ''
Write-Host 'RUNNER DESTRAVADO E RODADA LIMPA CONCLUIDA' -ForegroundColor Green
Write-Host 'O Pulse V1 permanece ativo.' -ForegroundColor Green
