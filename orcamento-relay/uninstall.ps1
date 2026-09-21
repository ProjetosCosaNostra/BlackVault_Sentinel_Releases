$ErrorActionPreference = 'Stop'
$Base     = Join-Path $env:LOCALAPPDATA 'BlackGold\OrcamentoRelay'
$TaskName = 'BlackGold_Orcamento_Relay_V3'
& schtasks.exe /Delete /TN $TaskName /F 2>$null | Out-Null
Remove-Item -LiteralPath (Join-Path $Base 'RUN_RELAY_V3.ps1') -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath (Join-Path $Base 'RUN_RELAY_V3_HIDDEN.vbs') -Force -ErrorAction SilentlyContinue
Write-Host 'BlackGold Orçamento Relay V3 desativado.' -ForegroundColor Green
Write-Host 'O clone autenticado e os backups do projeto foram preservados.' -ForegroundColor Cyan
