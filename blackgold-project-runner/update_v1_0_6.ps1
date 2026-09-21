$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_0_6.new.ps1'
$TaskName = 'BlackGold_Project_Runner_V1'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/758cf2456acc280d30cec66b32eeee03a2deb36d/blackgold-project-runner/runner.ps1'

if (-not (Test-Path -LiteralPath $Base)) { throw "Runner nao instalado em $Base" }
Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'Download do Runner V1.0.6 falhou.' }

$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.0\.6'") { throw 'Arquivo baixado nao e V1.0.6.' }
if ($text -match 'Invoke-Expression|iex\s') { throw 'Atualizacao recusada: execucao arbitraria detectada.' }

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($TempPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    throw ("Runner recusado pelo parser nativo do PowerShell: " + $messages)
}

Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

Write-Host 'RUNNER V1.0.6 VALIDADO PELO PARSER E INSTALADO' -ForegroundColor Green
Write-Host 'Executando somente o patch da Home; o emulador so sera liberado depois do build PASS.' -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if ($LASTEXITCODE -ne 0) { throw "Runner terminou com codigo $LASTEXITCODE" }

Start-ScheduledTask -TaskName $TaskName
Write-Host 'Rodada concluida e tarefa automatica reativada.' -ForegroundColor Green
