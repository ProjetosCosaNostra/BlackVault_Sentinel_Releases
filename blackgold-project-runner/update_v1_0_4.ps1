$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_0_4.new.ps1'
$TaskName = 'BlackGold_Project_Runner_V1'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/d3691f18912d50001693e1240556417c5f47daa2/blackgold-project-runner/runner.ps1'

if (-not (Test-Path -LiteralPath $Base)) { throw "Runner nao instalado em $Base" }
Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'Download do Runner V1.0.4 falhou.' }
$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.0\.4'") { throw 'Arquivo baixado nao e V1.0.4.' }
if ($text -match 'Invoke-Expression|iex\s') { throw 'Atualizacao recusada: execucao arbitraria detectada.' }
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

Write-Host 'RUNNER V1.0.4 INSTALADO' -ForegroundColor Green
Write-Host '1/2 Aplicando Home aprovada com backup e build...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if ($LASTEXITCODE -ne 0) { throw "Primeira rodada do Runner falhou: $LASTEXITCODE" }

Write-Host '2/2 Validando no emulador, instalando e abrindo o app...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if ($LASTEXITCODE -ne 0) { throw "Segunda rodada do Runner falhou: $LASTEXITCODE" }

Start-ScheduledTask -TaskName $TaskName
Write-Host ''
Write-Host 'V1.0.4 concluida. O emulador deve estar aberto com o app validado.' -ForegroundColor Green
