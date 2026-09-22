$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$TempPath = Join-Path $Base 'runner.v1_2_2.new.ps1'
$ControlRepo = Join-Path $Base 'control'
$PulseTask = 'BlackGold_Project_Runner_Pulse_V1'
$Branch = 'blackgold-project-runner-v1'
$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/0f8d405888271e1029d8f1b0471fd0070af3da16/blackgold-project-runner/runner.ps1'
$JobName = '027-orcamento-home-approved-exact-r3-visual-gate-001.json'
$JobId = 'orcamento-home-approved-exact-r3-visual-gate-001'

if (-not (Test-Path -LiteralPath $Base)) { throw "Runner base nao encontrada: $Base" }
if (-not (Test-Path -LiteralPath (Join-Path $ControlRepo '.git'))) { throw "Control repo nao encontrado: $ControlRepo" }

Import-Module ScheduledTasks -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskName $PulseTask -ErrorAction SilentlyContinue

$escapedRunner = [regex]::Escape($RunnerPath)
$procs = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.ProcessId -ne $PID -and $_.CommandLine -and $_.CommandLine -match $escapedRunner
})
foreach($p in $procs){ Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }
Remove-Item -LiteralPath (Join-Path $Base 'runner.lock') -Force -ErrorAction SilentlyContinue

Write-Host '[1/5] Baixando Runner V1.2.2...' -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $TempPath
$text = Get-Content -LiteralPath $TempPath -Raw
if ($text -notmatch "RunnerVersion\s*=\s*'1\.2\.2'") { throw 'Arquivo baixado nao e Runner V1.2.2.' }
if ($text -match 'Invoke-Expression|iex\s') { throw 'Atualizacao recusada: execucao arbitraria detectada.' }

Write-Host '[2/5] Validando sintaxe do Runner...' -ForegroundColor Cyan
$tokens=$null; $errors=$null
[System.Management.Automation.Language.Parser]::ParseFile($TempPath,[ref]$tokens,[ref]$errors) | Out-Null
if($errors.Count -gt 0){ throw ('Runner V1.2.2 recusado pelo parser: ' + (($errors | ForEach-Object {$_.Message}) -join ' | ')) }
Move-Item -LiteralPath $TempPath -Destination $RunnerPath -Force

Write-Host '[3/5] Preparando Visual Gate do Orçamento no Ponto...' -ForegroundColor Cyan
$git = (Get-Command git.exe -ErrorAction Stop).Source
& $git -C $ControlRepo fetch origin $Branch | Out-Null
if($LASTEXITCODE -ne 0){ throw 'Falha no fetch do control repo.' }
& $git -C $ControlRepo checkout $Branch | Out-Null
if($LASTEXITCODE -ne 0){ throw 'Falha no checkout do control repo.' }
& $git -C $ControlRepo reset --hard ("origin/" + $Branch) | Out-Null
if($LASTEXITCODE -ne 0){ throw 'Falha no reset do control repo.' }

$jobDir = Join-Path $ControlRepo 'project_runner\jobs\inbox'
[IO.Directory]::CreateDirectory($jobDir) | Out-Null
$jobPath = Join-Path $jobDir $JobName
$job = [ordered]@{
  schema='blackgold.project-runner.job.v1'
  id=$JobId
  project='orcamento_no_ponto'
  action='visual_gate'
  args=[ordered]@{
    golden_path='01_Android_App\orcamento_no_ponto\app\src\main\res\drawable-nodpi\home_reference_760.png'
    ensure_launch=$true
    activity='.MainActivity'
    crop_x=0
    crop_y=0
    width=760
    height=1350
    channel_tolerance=2
    max_mismatch_ratio=0.002
  }
}
$jobJson = $job | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($jobPath,$jobJson,[Text.UTF8Encoding]::new($false))

& $git -C $ControlRepo add -- ('project_runner/jobs/inbox/' + $JobName)
$pending = & $git -C $ControlRepo status --porcelain -- ('project_runner/jobs/inbox/' + $JobName)
if($pending){
  & $git -C $ControlRepo config user.name 'BlackGold Project Runner Updater'
  & $git -C $ControlRepo config user.email 'blackgold-project-runner@local.invalid'
  & $git -C $ControlRepo commit -m 'runner: queue Orçamento Home R3 visual gate' | Out-Null
  if($LASTEXITCODE -ne 0){ throw 'Falha ao registrar Visual Gate.' }
  & $git -C $ControlRepo push origin $Branch | Out-Null
  if($LASTEXITCODE -ne 0){ throw 'Falha ao publicar Visual Gate.' }
}

Write-Host '[4/5] Executando Visual Gate agora...' -ForegroundColor Cyan
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $RunnerPath
if($LASTEXITCODE -ne 0){ throw "Runner terminou com codigo $LASTEXITCODE" }

& $git -C $ControlRepo fetch origin $Branch | Out-Null
& $git -C $ControlRepo reset --hard ("origin/" + $Branch) | Out-Null
$resultPath = Join-Path $ControlRepo ('project_runner\jobs\outbox\' + $JobId + '.json')
if(-not (Test-Path -LiteralPath $resultPath)){ throw 'Visual Gate nao publicou resultado.' }
$result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
if($result.status -ne 'success'){ throw ('Visual Gate falhou: ' + $result.error) }

Write-Host '[5/5] Resultado...' -ForegroundColor Cyan
$gate = $result.data
if($gate.pass){
  Write-Host 'VISUAL GATE: PASS' -ForegroundColor Green
} else {
  Write-Host 'VISUAL GATE: FAIL' -ForegroundColor Red
}
Write-Host ('Mismatch pixels: ' + $gate.mismatch_pixels)
Write-Host ('Mismatch ratio: ' + $gate.mismatch_ratio)
Write-Host ('Mean abs channel delta: ' + $gate.mean_abs_channel_delta)
Write-Host ('Max channel delta: ' + $gate.max_channel_delta)
Write-Host ('Golden SHA256: ' + $gate.golden_sha256)
Write-Host ('Runtime SHA256: ' + $gate.runtime_sha256)

Start-ScheduledTask -TaskName $PulseTask -ErrorAction SilentlyContinue
