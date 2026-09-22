$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_2_4.new.ps1'
$PulseTask = 'BlackGold_Project_Runner_Pulse_V1'
$ControlRepo = Join-Path $Base 'control'
$ControlBranch = 'blackgold-project-runner-v1'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/3326f27ac915dcc93e8a9854c586bf13f6488b8c/blackgold-project-runner/runner.ps1'
$git = (Get-Command git.exe -ErrorAction Stop).Source

if (-not (Test-Path -LiteralPath $Base)) { throw "Runner nao instalado em $Base" }
if (-not (Test-Path -LiteralPath (Join-Path $ControlRepo '.git'))) { throw "Control plane nao encontrado em $ControlRepo" }

Import-Module ScheduledTasks -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName $PulseTask -ErrorAction SilentlyContinue

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
if (-not (Test-Path -LiteralPath $TempPath)) { throw 'Download do Runner V1.2.4 falhou.' }
$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.2\.4'") { throw 'Arquivo baixado nao e Runner V1.2.4.' }
if ($text -match 'Invoke-Expression|iex\s') { throw 'Atualizacao recusada: execucao arbitraria detectada.' }

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($TempPath,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    throw ("Runner recusado pelo parser: " + $messages)
}

Copy-Item -LiteralPath $RunnerPath -Destination (Join-Path $Base 'runner.before_v1_2_4.ps1') -Force
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

& $git -C $ControlRepo fetch origin $ControlBranch | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha no git fetch do control plane.' }
& $git -C $ControlRepo checkout $ControlBranch | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha no git checkout do control plane.' }
& $git -C $ControlRepo reset --hard ("origin/" + $ControlBranch) | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha no git reset do control plane.' }

$jobDir = Join-Path $ControlRepo 'project_runner\jobs\inbox'
[IO.Directory]::CreateDirectory($jobDir) | Out-Null
$jobPath = Join-Path $jobDir '031-orcamento-home-r3-visual-gate-correct-avd-001.json'
$jobJson = @'
{
  "schema": "blackgold.project-runner.job.v1",
  "id": "orcamento-home-r3-visual-gate-correct-avd-001",
  "project": "orcamento_no_ponto",
  "action": "visual_gate",
  "args": {
    "golden_path": "01_Android_App\\orcamento_no_ponto\\app\\src\\main\\res\\drawable-nodpi\\home_reference_760.png",
    "ensure_launch": true,
    "activity": ".MainActivity",
    "crop_x": 0,
    "crop_y": 0,
    "width": 760,
    "height": 1350,
    "channel_tolerance": 3,
    "max_mismatch_ratio": 0.002
  }
}
'@
[IO.File]::WriteAllText($jobPath,$jobJson,[Text.UTF8Encoding]::new($false))
& $git -C $ControlRepo add -- 'project_runner/jobs/inbox/031-orcamento-home-r3-visual-gate-correct-avd-001.json'
$pending = & $git -C $ControlRepo status --porcelain -- 'project_runner/jobs/inbox/031-orcamento-home-r3-visual-gate-correct-avd-001.json'
if ($pending) {
    & $git -C $ControlRepo config user.name 'BlackGold Project Runner Updater'
    & $git -C $ControlRepo config user.email 'blackgold-project-runner@local.invalid'
    & $git -C $ControlRepo commit -m 'runner: queue Orçamento Home R3 visual gate on protected AVD' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao registrar visual gate job.' }
    & $git -C $ControlRepo push origin $ControlBranch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao publicar visual gate job.' }
}

Write-Host 'RUNNER V1.2.4 INSTALADO E VALIDADO' -ForegroundColor Green
Write-Host 'Protecao ativa: Orçamento recusa emulator-5554.' -ForegroundColor Yellow
Write-Host 'Executando Visual Gate no AVD correto agora...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if ($LASTEXITCODE -ne 0) { throw "Runner terminou com codigo $LASTEXITCODE" }

Start-ScheduledTask -TaskName $PulseTask -ErrorAction SilentlyContinue
Write-Host 'Visual Gate executado; Pulse V1 reativado.' -ForegroundColor Green
