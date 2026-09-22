$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_0_9.new.ps1'
$BackupPath = Join-Path $Base ('runner.before-v1_0_9.' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.ps1')
$TaskName = 'BlackGold_Project_Runner_V1'
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/c15bd2a1263390197c52b81ba41f3f7f9e6987d7/blackgold-project-runner/runner.ps1'

if (-not (Test-Path -LiteralPath $Base)) { throw "Runner base nao encontrada: $Base" }

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'Download do Runner V1.0.9 falhou.' }

$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.0\.9'") { throw 'Arquivo baixado nao e Runner V1.0.9.' }
if ($text -match 'Invoke-Expression|iex\s') { throw 'Atualizacao recusada: execucao arbitraria detectada.' }

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($TempPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    throw ("Runner recusado pelo parser nativo do PowerShell: " + $messages)
}

Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

if (Test-Path -LiteralPath $RunnerPath) {
    Copy-Item -LiteralPath $RunnerPath -Destination $BackupPath -Force
}
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $RunnerPath + '"'
$action = New-ScheduledTaskAction -Execute $ps -Argument $arguments
$repeat = New-ScheduledTaskTrigger -Once -At (Get-Date).AddSeconds(20) -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration (New-TimeSpan -Days 3650)
$logon = New-ScheduledTaskTrigger -AtLogOn -User ([Security.Principal.WindowsIdentity]::GetCurrent().Name)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 45)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger @($repeat,$logon) -Settings $settings -Principal $principal -Force | Out-Null

Write-Host 'Runner V1.0.9 instalado e agendamento reconstruido.' -ForegroundColor Green

for ($i = 1; $i -le 2; $i++) {
    Write-Host ("Executando rodada imediata " + $i + "/2...") -ForegroundColor Cyan
    & $ps -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
    if ($LASTEXITCODE -ne 0) { throw "Runner terminou com codigo $LASTEXITCODE na rodada $i" }
    Start-Sleep -Seconds 3
}

Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Write-Host 'BLACKGOLD PROJECT RUNNER V1.0.9 ATIVO' -ForegroundColor Green
Write-Host ('Backup anterior: ' + $BackupPath) -ForegroundColor DarkGray
