$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$WatchdogPath = Join-Path $Base 'watchdog.ps1'
$WatchdogTemp = Join-Path $Base 'watchdog.next.ps1'
$OldTask = 'BlackGold_Project_Runner_V1'
$TaskName = 'BlackGold_Project_Runner_Watchdog_V1'
$PowerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$WatchdogUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/29e7433435a33287687b3386512976cbba4eda80/blackgold-project-runner/watchdog_v1.ps1'

if (-not (Test-Path -LiteralPath $RunnerPath)) { throw "Runner nao encontrado: $RunnerPath" }
New-Item -ItemType Directory -Force -Path $Base | Out-Null

Write-Host '[1/4] Baixando watchdog...' -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing -Uri $WatchdogUrl -OutFile $WatchdogTemp
if (-not (Test-Path -LiteralPath $WatchdogTemp)) { throw 'Falha ao baixar watchdog.' }

Write-Host '[2/4] Validando sintaxe...' -ForegroundColor Cyan
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($WatchdogTemp,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    Remove-Item -LiteralPath $WatchdogTemp -Force -ErrorAction SilentlyContinue
    throw ("Watchdog recusado pelo parser: " + $messages)
}
Move-Item -LiteralPath $WatchdogTemp -Destination $WatchdogPath -Force

Write-Host '[3/4] Instalando watchdog persistente...' -ForegroundColor Cyan
Import-Module ScheduledTasks -ErrorAction Stop
Disable-ScheduledTask -TaskName $OldTask -ErrorAction SilentlyContinue | Out-Null
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $WatchdogPath + '"'
$action = New-ScheduledTaskAction -Execute $PowerShell -Argument $arguments
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$triggerRecovery = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(15) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Days 1) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($triggerLogon,$triggerRecovery) -Settings $settings -Principal $principal -Force | Out-Null

Write-Host '[4/4] Iniciando watchdog...' -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2
$task = Get-ScheduledTask -TaskName $TaskName
Write-Host ''
Write-Host 'BLACKGOLD PROJECT RUNNER WATCHDOG V1 ATIVO' -ForegroundColor Green
Write-Host ("Estado: " + $task.State) -ForegroundColor Green
Write-Host 'O job pendente da Home aprovada exata sera consumido automaticamente.' -ForegroundColor Cyan
