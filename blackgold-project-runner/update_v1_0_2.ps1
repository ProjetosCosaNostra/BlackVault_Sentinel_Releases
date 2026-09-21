$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.next.ps1'
$TaskName = 'BlackGold_Project_Runner_V1'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/d3004db0690e1af25ed2b6e74b512a16d51158f4/blackgold-project-runner/runner.ps1'

if (-not (Test-Path -LiteralPath $Base)) { throw "BlackGold Project Runner nao esta instalado em $Base" }

Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'Falha ao baixar Runner V1.0.2' }

$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.0\.2'") { throw 'Arquivo baixado nao e Runner V1.0.2' }
if ($text -match 'Invoke-Expression|iex\s') { throw 'Atualizacao recusada: execucao arbitraria detectada.' }

Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force
Start-ScheduledTask -TaskName $TaskName

Write-Host ''
Write-Host 'BLACKGOLD PROJECT RUNNER ATUALIZADO PARA V1.0.2' -ForegroundColor Green
Write-Host 'A tarefa foi reativada e a nova rodada foi disparada.' -ForegroundColor Cyan
Write-Host 'Job aguardando: orcamento-smoke-v1-004' -ForegroundColor Yellow
