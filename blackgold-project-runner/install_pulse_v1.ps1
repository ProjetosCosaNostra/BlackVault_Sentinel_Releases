$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$OldWatchdog = 'BlackGold_Project_Runner_Watchdog_V1'
$OldRunnerTask = 'BlackGold_Project_Runner_V1'
$TaskName = 'BlackGold_Project_Runner_Pulse_V1'
$PowerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

if (-not (Test-Path -LiteralPath $RunnerPath)) { throw "Runner nao encontrado: $RunnerPath" }

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($RunnerPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    throw ("Runner local invalido: " + $messages)
}

Import-Module ScheduledTasks -ErrorAction Stop
Unregister-ScheduledTask -TaskName $OldWatchdog -Confirm:$false -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $OldRunnerTask -Confirm:$false -ErrorAction SilentlyContinue

$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $RunnerPath + '"'
$action = New-ScheduledTaskAction -Execute $PowerShell -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(20) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$logon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($trigger,$logon) -Settings $settings -Principal $principal -Force | Out-Null

Write-Host 'PULSE V1 instalado: uma execucao do Runner por minuto.' -ForegroundColor Green
Write-Host 'Executando uma rodada imediata para consumir o patch R2...' -ForegroundColor Cyan
& $PowerShell -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if ($LASTEXITCODE -ne 0) { throw "Runner imediato terminou com codigo $LASTEXITCODE" }

$task = Get-ScheduledTask -TaskName $TaskName
Write-Host ("Tarefa: " + $task.TaskName + " | Estado: " + $task.State) -ForegroundColor Green
