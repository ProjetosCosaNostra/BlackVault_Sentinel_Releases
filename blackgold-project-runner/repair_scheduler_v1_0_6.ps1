$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TaskName = 'BlackGold_Project_Runner_V1'
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

if (-not (Test-Path -LiteralPath $RunnerPath)) { throw "Runner nao encontrado: $RunnerPath" }
$runnerText = Get-Content -LiteralPath $RunnerPath -Raw
if ($runnerText -notmatch "RunnerVersion\s*=\s*'1\.0\.6'") { throw 'Runner local nao esta na V1.0.6.' }

Import-Module ScheduledTasks -ErrorAction Stop
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $RunnerPath + '"'
$action = New-ScheduledTaskAction -Execute $ps -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(20) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 45)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Host 'AGENDAMENTO CORRIGIDO: repeticao a cada 1 minuto por 10 anos.' -ForegroundColor Green
Write-Host 'Executando o Runner agora para consumir o smoke pendente...' -ForegroundColor Cyan
& $ps -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if ($LASTEXITCODE -ne 0) { throw "Runner terminou com codigo $LASTEXITCODE" }

$task = Get-ScheduledTask -TaskName $TaskName
Write-Host ("Tarefa: " + $task.TaskName + " | Estado: " + $task.State) -ForegroundColor Cyan
Write-Host 'Smoke do Orçamento no Ponto foi disparado.' -ForegroundColor Yellow
