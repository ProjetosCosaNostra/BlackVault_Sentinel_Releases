$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Project = 'E:\Orcamento_no_Ponto'
$Base = Join-Path $env:LOCALAPPDATA 'BlackGold\OrcamentoRelay'
$Repo = Join-Path $Base 'repo'
$Branch = 'orcamento-no-ponto-relay'
$Client = Join-Path $Repo 'relay\Orcamento_no_Ponto\client\PROJECT_RELAY_CLIENT.ps1'
$Request = Join-Path $Repo 'relay\Orcamento_no_Ponto\runtime\REQUEST.txt'
$TaskName = 'BlackGold_Orcamento_Relay_V3'
$Git = (Get-Command git.exe -ErrorAction Stop).Source
$Ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

function Fail([string]$Message) { throw "[ORCAMENTO_RECOVERY] $Message" }

if (-not (Test-Path -LiteralPath $Project)) { Fail "Projeto nao encontrado: $Project" }
if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) { Fail "Relay local nao encontrado: $Repo" }

$origin = (& $Git -C $Repo remote get-url origin 2>$null | Out-String).Trim()
if ($origin -notmatch 'ProjetosCosaNostra[/\\]BlackVault_Sentinel') {
    Fail "Origin inesperado: $origin"
}

Write-Host '1/4 Sincronizando relay seguro...' -ForegroundColor Cyan
& $Git -C $Repo fetch origin $Branch
if ($LASTEXITCODE -ne 0) { Fail 'git fetch falhou' }
& $Git -C $Repo checkout $Branch
if ($LASTEXITCODE -ne 0) { Fail 'git checkout falhou' }
& $Git -C $Repo reset --hard ("origin/" + $Branch)
if ($LASTEXITCODE -ne 0) { Fail 'git reset falhou' }

if (-not (Test-Path -LiteralPath $Client)) { Fail "Cliente nao encontrado: $Client" }

Write-Host '2/4 Armando recuperacao exclusiva do Orçamento no Ponto...' -ForegroundColor Cyan
$requestId = 'RECOVER_OPEN_' + (Get-Date -Format 'yyyyMMdd_HHmmss')
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Request) | Out-Null
[IO.File]::WriteAllText($Request, $requestId + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))

Push-Location $Repo
try {
    & $Git add -- 'relay/Orcamento_no_Ponto/runtime/REQUEST.txt'
    $changes = & $Git status --porcelain -- 'relay/Orcamento_no_Ponto/runtime/REQUEST.txt'
    if ($changes) {
        & $Git config user.name 'BlackGold Orçamento Recovery'
        & $Git config user.email 'blackgold-recovery@local.invalid'
        & $Git commit -m ("relay: request runtime recovery " + $requestId) | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'git commit falhou' }
        & $Git pull --rebase origin $Branch | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'git pull --rebase falhou' }
        & $Git push origin $Branch | Out-Null
        if ($LASTEXITCODE -ne 0) { Fail 'git push falhou' }
    }
}
finally {
    Pop-Location
}

Write-Host '3/4 Executando recuperação agora...' -ForegroundColor Cyan
& $Ps -NoProfile -ExecutionPolicy Bypass -File $Client
if ($LASTEXITCODE -ne 0) { Fail "Cliente falhou com codigo $LASTEXITCODE" }

Write-Host '4/4 Reativando execução automática a cada 5 minutos...' -ForegroundColor Cyan
$Runner = Join-Path $Base 'RUN_RELAY_V3.ps1'
$Hidden = Join-Path $Base 'RUN_RELAY_V3_HIDDEN.vbs'
if ((Test-Path -LiteralPath $Runner) -and (Test-Path -LiteralPath $Hidden)) {
    $taskCmd = 'wscript.exe "' + $Hidden + '"'
    & schtasks.exe /Create /TN $TaskName /SC MINUTE /MO 5 /TR $taskCmd /F | Out-Null
}

$resultPath = Join-Path $Repo ('relay\Orcamento_no_Ponto\runtime\RESULT_' + $requestId + '.txt')
if (-not (Test-Path -LiteralPath $resultPath)) {
    Fail "Resultado da recuperação não foi produzido: $resultPath"
}

$result = Get-Content -LiteralPath $resultPath -Raw
Write-Host ''
Write-Host $result
if ($result -notmatch '(?m)^status=PASS\s*$') {
    Fail 'O app ainda nao abriu. O diagnostico acima identifica a causa.'
}

Write-Host ''
Write-Host 'ORÇAMENTO NO PONTO ABERTO NO EMULADOR CORRETO.' -ForegroundColor Green
