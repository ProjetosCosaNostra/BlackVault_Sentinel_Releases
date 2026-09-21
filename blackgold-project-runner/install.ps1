$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Version = '1.0.0'
$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$ConfigPath = Join-Path $Base 'projects.json'
$ControlRepo = Join-Path $Base 'control'
$LogsDir = Join-Path $Base 'logs'
$TaskName = 'BlackGold_Project_Runner_V1'
$ControlBranch = 'blackgold-project-runner-v1'
$ControlUrl = 'https://github.com/ProjetosCosaNostra/BlackVault_Sentinel.git'

$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/74a465a42e5d6ad9f8a37dad9dbb64e16c225bdd/blackgold-project-runner/runner.ps1'
$ConfigUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/4bb1ef6a88e765c1d9fd309974c776ebc219447e/blackgold-project-runner/projects.default.json'

New-Item -ItemType Directory -Force -Path $Base,$LogsDir | Out-Null

$git = (Get-Command git.exe -ErrorAction Stop).Source
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

Write-Host '[1/5] Preparando control plane privado...' -ForegroundColor Cyan
if (Test-Path -LiteralPath (Join-Path $ControlRepo '.git')) {
    & $git -C $ControlRepo fetch origin $ControlBranch
    if ($LASTEXITCODE -ne 0) { throw 'Falha no git fetch do Project Runner.' }
    & $git -C $ControlRepo checkout $ControlBranch
    if ($LASTEXITCODE -ne 0) { throw 'Falha no git checkout do Project Runner.' }
    & $git -C $ControlRepo reset --hard ("origin/" + $ControlBranch)
    if ($LASTEXITCODE -ne 0) { throw 'Falha no git reset do Project Runner.' }
} else {
    & $git clone --branch $ControlBranch --single-branch $ControlUrl $ControlRepo
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao clonar o control plane privado.' }
}
& $git -C $ControlRepo config core.longpaths true

Write-Host '[2/5] Instalando Runner V1...' -ForegroundColor Cyan
Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $RunnerPath
if (-not (Test-Path -LiteralPath $RunnerPath)) { throw 'runner.ps1 nao foi baixado.' }
$runnerText = Get-Content -LiteralPath $RunnerPath -Raw
if ($runnerText -notmatch "RunnerVersion\s*=\s*'1\.0\.0'") {
    throw 'Runner baixado nao corresponde a V1 esperada.'
}
if ($runnerText -match 'Invoke-Expression|iex\s') {
    throw 'Runner recusado: encontrou execucao arbitraria.'
}

if (-not (Test-Path -LiteralPath $ConfigPath)) {
    Invoke-WebRequest -UseBasicParsing -Uri $ConfigUrl -OutFile $ConfigPath
}
$config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
if (-not (@($config.projects | Where-Object { $_.id -eq 'orcamento_no_ponto' }).Count)) {
    throw 'Registro do Orcamento no Ponto nao encontrado.'
}

Write-Host '[3/5] Criando utilitarios locais...' -ForegroundColor Cyan
$runNow = "& '$ps' -NoProfile -ExecutionPolicy Bypass -File '$RunnerPath'" + [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $Base 'RUN_NOW.ps1'),$runNow,[Text.UTF8Encoding]::new($false))

$statusLines = @(
    '$ErrorActionPreference = ''SilentlyContinue''',
    "Write-Host 'BlackGold Project Runner V1' -ForegroundColor Cyan",
    "Get-ScheduledTask -TaskName '$TaskName' | Format-List TaskName,State",
    "Write-Host ''",
    "Write-Host 'Base: $Base'",
    "Write-Host 'Control: $ControlRepo'",
    "Write-Host 'Config: $ConfigPath'",
    "Write-Host ''",
    "Get-Content -LiteralPath '$ConfigPath' -Raw"
)
$statusText = $statusLines -join [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $Base 'STATUS.ps1'),$statusText,[Text.UTF8Encoding]::new($false))

Write-Host '[4/5] Instalando execucao automatica oculta...' -ForegroundColor Cyan
Import-Module ScheduledTasks -ErrorAction Stop
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $RunnerPath + '"'
$action = New-ScheduledTaskAction -Execute $ps -Argument $arguments
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 1)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 45)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null

Write-Host '[5/5] Executando primeira rodada...' -ForegroundColor Cyan
$runArgs = '-NoProfile -ExecutionPolicy Bypass -File "' + $RunnerPath + '"'
Start-Process -FilePath $ps -WindowStyle Hidden -ArgumentList $runArgs | Out-Null

Write-Host ''
Write-Host 'BLACKGOLD PROJECT RUNNER V1 INSTALADO' -ForegroundColor Green
Write-Host "Versao: $Version" -ForegroundColor Green
Write-Host "Base local: $Base" -ForegroundColor Cyan
Write-Host "Tarefa: $TaskName (1 minuto, oculta)" -ForegroundColor Cyan
Write-Host 'Projeto inicial: Orcamento no Ponto' -ForegroundColor Cyan
Write-Host 'Job inicial: build + emulator + install + launch + screenshot' -ForegroundColor Yellow
Write-Host ''
Write-Host 'Nao usa Desktop Commander e nao aceita comandos remotos arbitrarios.' -ForegroundColor Yellow
