$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.next.ps1'
$TaskName = 'BlackGold_Project_Runner_V1'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/03379ca5451cf1c65d6338083edb69c3ff0cb98b/blackgold-project-runner/runner.ps1'

if (-not (Test-Path -LiteralPath $Base)) { throw "BlackGold Project Runner nao esta instalado em $Base" }
Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'Falha ao baixar Runner V1.0.3' }
$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.0\.3'") { throw 'Arquivo baixado nao e Runner V1.0.3' }
if ($text -match 'Invoke-Expression|iex\s') { throw 'Atualizacao recusada: execucao arbitraria detectada.' }
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

$ControlRepo = Join-Path $Base 'control'
$ControlBranch = 'blackgold-project-runner-v1'
$git = (Get-Command git.exe -ErrorAction Stop).Source

& $git -C $ControlRepo fetch origin $ControlBranch | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha ao atualizar fila privada.' }
& $git -C $ControlRepo checkout $ControlBranch | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha ao abrir branch da fila privada.' }
& $git -C $ControlRepo reset --hard ("origin/" + $ControlBranch) | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha ao sincronizar fila privada.' }

$jobDir = Join-Path $ControlRepo 'project_runner\jobs\inbox'
[IO.Directory]::CreateDirectory($jobDir) | Out-Null
$jobPath = Join-Path $jobDir '005-orcamento-home-approved-v13-apply-002.json'
$jobJson = @'
{
  "schema": "blackgold.project-runner.job.v1",
  "id": "orcamento-home-approved-v13-apply-002",
  "project": "orcamento_no_ponto",
  "action": "apply_patch",
  "args": {
    "payload_dir": "project_runner\\payloads\\orcamento-home-approved-v13",
    "verify_build": true
  }
}
'@
[IO.File]::WriteAllText($jobPath,$jobJson,[Text.UTF8Encoding]::new($false))

& $git -C $ControlRepo add -- 'project_runner/jobs/inbox/005-orcamento-home-approved-v13-apply-002.json'
$pending = & $git -C $ControlRepo status --porcelain -- 'project_runner/jobs/inbox/005-orcamento-home-approved-v13-apply-002.json'
if ($pending) {
    & $git -C $ControlRepo config user.name 'BlackGold Project Runner Installer'
    & $git -C $ControlRepo config user.email 'blackgold-project-runner@local.invalid'
    & $git -C $ControlRepo commit -m 'runner: queue approved Home V13 apply retry' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao registrar job da Home aprovada.' }
    & $git -C $ControlRepo push origin $ControlBranch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar job da Home aprovada.' }
}

Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Milliseconds 500
& $RunnerPath
Write-Host ''
Write-Host 'BLACKGOLD PROJECT RUNNER ATUALIZADO PARA V1.0.3' -ForegroundColor Green
Write-Host 'Backup de patch movido para caminho curto e confiavel.' -ForegroundColor Cyan
Write-Host 'A tarefa foi reativada; a Home aprovada foi enfileirada e executada.' -ForegroundColor Cyan
