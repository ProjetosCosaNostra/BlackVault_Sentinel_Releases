$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_2_2.new.ps1'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/8c56394170dc17b35480d6c8e67a4b43944007fd/blackgold-project-runner/runner.ps1'

if (-not (Test-Path -LiteralPath $Base)) { throw "Runner nao instalado em $Base" }

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'Download do Runner V1.2.2 falhou.' }

$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.2\.2'") { throw 'Arquivo baixado nao e Runner V1.2.2.' }
if ($text -match 'Invoke-Expression|iex\s') { throw 'Atualizacao recusada: execucao arbitraria detectada.' }

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($TempPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    throw ("Runner recusado pelo parser: " + $messages)
}

Copy-Item -LiteralPath $RunnerPath -Destination (Join-Path $Base 'runner.v1_1_2.backup.ps1') -Force
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

Write-Host 'BLACKGOLD PROJECT RUNNER ATUALIZADO PARA V1.2.2' -ForegroundColor Green
Write-Host 'Visual Gate pixel-a-pixel disponivel.' -ForegroundColor Cyan
Write-Host 'O Pulse V1 continuara executando automaticamente.' -ForegroundColor Cyan
