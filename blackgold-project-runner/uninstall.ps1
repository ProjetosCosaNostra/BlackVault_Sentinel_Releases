$ErrorActionPreference = 'Stop'
$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$TaskName = 'BlackGold_Project_Runner_V1'

Import-Module ScheduledTasks -ErrorAction SilentlyContinue
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Write-Host 'BlackGold Project Runner V1 desativado.' -ForegroundColor Green
Write-Host "Arquivos locais preservados em: $Base" -ForegroundColor Cyan
