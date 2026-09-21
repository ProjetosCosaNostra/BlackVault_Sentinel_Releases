$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_0_7.new.ps1'
$TaskName = 'BlackGold_Project_Runner_V1'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/33d62038e8cf19b35f52d8659911981b68f344bd/blackgold-project-runner/runner.ps1'

if (-not (Test-Path -LiteralPath $Base)) {
    throw "Runner nao instalado em $Base"
}

Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath

if (-not (Test-Path -LiteralPath $TempPath)) {
    throw 'Download do Runner V1.0.7 falhou.'
}

$text = Get-Content -LiteralPath $TempPath -Raw

if ($text -notmatch "RunnerVersion\s*=\s*'1\.0\.7'") {
    throw 'Arquivo baixado nao e V1.0.7.'
}

if ($text -match 'Invoke-Expression|iex\s') {
    throw 'Atualizacao recusada: execucao arbitraria detectada.'
}

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $TempPath,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -gt 0) {
    $messages = (
        $parseErrors |
            ForEach-Object { $_.Message }
    ) -join ' | '

    Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    throw ("Runner recusado pelo parser nativo do PowerShell: " + $messages)
}

Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

Write-Host ''
Write-Host 'BLACKGOLD PROJECT RUNNER V1.0.7 INSTALADO' -ForegroundColor Green
Write-Host 'Executando agora o proximo job pendente da fila...' -ForegroundColor Cyan

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
$code = $LASTEXITCODE

if ($code -ne 0) {
    throw "Runner terminou com codigo $code"
}

Start-ScheduledTask -TaskName $TaskName

Write-Host ''
Write-Host 'TAREFA AUTOMATICA REATIVADA' -ForegroundColor Green
Write-Host 'A proxima rodada continuara consumindo a fila privada.' -ForegroundColor Cyan
