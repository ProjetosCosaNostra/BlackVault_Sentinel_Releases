$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$RunnerTemp = Join-Path $Base 'runner.v1_1_2.new.ps1'
$WrapperPath = Join-Path $Base 'run_orcamento_no_ponto.ps1'
$TaskName = 'BlackGold_Project_Runner_Orcamento_Pulse_V1'
$PowerShell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/f59238f6322cf236c7aaa637a8f301b2e11f120b/blackgold-project-runner/runner.ps1'

New-Item -ItemType Directory -Force -Path $Base | Out-Null

Write-Host '[1/5] Baixando Runner 1.1.2 isolado...' -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $RunnerTemp
if (-not (Test-Path -LiteralPath $RunnerTemp)) { throw 'Falha ao baixar Runner 1.1.2.' }

Write-Host '[2/5] Validando Runner com parser nativo...' -ForegroundColor Cyan
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($RunnerTemp,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) { throw ('Runner invalido: ' + (($errors | ForEach-Object {$_.Message}) -join ' | ')) }
$runnerText = Get-Content -LiteralPath $RunnerTemp -Raw
if ($runnerText -notmatch "RunnerVersion\s*=\s*'1\.1\.2'") { throw 'Arquivo baixado nao e Runner 1.1.2.' }
Move-Item -LiteralPath $RunnerTemp -Destination $RunnerPath -Force

Write-Host '[3/5] Criando wrapper exclusivo do Orcamento no Ponto...' -ForegroundColor Cyan
$wrapper = @(
    '$ErrorActionPreference = ''Stop''' ,
    '$env:BLACKGOLD_PROJECT_FILTER = ''orcamento_no_ponto''' ,
    '& ''' + $RunnerPath + ''''
) -join [Environment]::NewLine
[IO.File]::WriteAllText($WrapperPath,$wrapper,[Text.UTF8Encoding]::new($false))

$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($WrapperPath,[ref]$tokens,[ref]$errors) | Out-Null
if ($errors.Count -gt 0) { throw ('Wrapper invalido: ' + (($errors | ForEach-Object {$_.Message}) -join ' | ')) }

Write-Host '[4/5] Instalando Pulse exclusivo do Orcamento...' -ForegroundColor Cyan
Import-Module ScheduledTasks -ErrorAction Stop
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $WrapperPath + '"'
$action = New-ScheduledTaskAction -Execute $PowerShell -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(20) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$logon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 20)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($trigger,$logon) -Settings $settings -Principal $principal -Force | Out-Null

Write-Host '[5/5] Disparando rodada exclusiva agora...' -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2
$task = Get-ScheduledTask -TaskName $TaskName
Write-Host ''
Write-Host 'PULSE EXCLUSIVO DO ORCAMENTO NO PONTO ATIVO' -ForegroundColor Green
Write-Host ('Runner: 1.1.2 | Estado: ' + $task.State) -ForegroundColor Green
Write-Host 'Filtro: orcamento_no_ponto' -ForegroundColor Yellow
Write-Host 'Junior Resolve nao sera consumido por esta tarefa.' -ForegroundColor Yellow
