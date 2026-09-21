$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_0_3.new.ps1'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/03379ca5451cf1c65d6338083edb69c3ff0cb98b/blackgold-project-runner/runner.ps1'

if (-not (Test-Path -LiteralPath $Base)) { throw "Runner nao instalado em $Base" }
Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'Download do Runner V1.0.3 falhou.' }
$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.0\.3'") { throw 'Arquivo baixado nao e V1.0.3.' }
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force
Write-Host 'RUNNER V1.0.3 INSTALADO' -ForegroundColor Green
Write-Host 'Executando agora...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if ($LASTEXITCODE -ne 0) { throw "Runner terminou com codigo $LASTEXITCODE" }
Write-Host 'Execucao concluida.' -ForegroundColor Green
