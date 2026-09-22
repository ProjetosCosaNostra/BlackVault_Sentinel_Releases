$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TaskName = 'BlackGold_Project_Runner_V1'
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

if (-not (Test-Path -LiteralPath $RunnerPath)) { throw "Runner nao encontrado: $RunnerPath" }

$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile($RunnerPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) { throw ('Runner local invalido: ' + (($errors | ForEach-Object {$_.Message}) -join ' | ')) }

Import-Module ScheduledTasks -ErrorAction Stop
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $RunnerPath + '"'
$action = New-ScheduledTaskAction -Execute $ps -Argument $arguments
$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(20) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$logon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 45)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($repeat,$logon) -Settings $settings -Principal $principal -Force | Out-Null

Write-Host 'Runner validado e agendamento refeito.' -ForegroundColor Green
Write-Host 'Executando uma rodada imediata agora...' -ForegroundColor Cyan
& $ps -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if ($LASTEXITCODE -ne 0) { throw "Runner terminou com codigo $LASTEXITCODE" }
Write-Host 'Rodada imediata concluida; tarefa ficou armada para 1 minuto + logon.' -ForegroundColor Green
