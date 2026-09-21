$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Branch   = 'orcamento-no-ponto-relay'
$Base     = Join-Path $env:LOCALAPPDATA 'BlackGold\OrcamentoRelay'
$Repo     = Join-Path $Base 'repo'
$Client   = Join-Path $Repo 'relay\Orcamento_no_Ponto\client\PROJECT_RELAY_CLIENT.ps1'
$Runner   = Join-Path $Base 'RUN_RELAY_V3.ps1'
$Hidden   = Join-Path $Base 'RUN_RELAY_V3_HIDDEN.vbs'
$LogDir   = Join-Path $Base 'logs'
$TaskName = 'BlackGold_Orcamento_Relay_V3'
$Project  = 'E:\Orcamento_no_Ponto'

function Fail([string]$Message) {
    throw "[ORCAMENTO_RELAY_V3] $Message"
}

if (-not (Test-Path -LiteralPath $Project)) {
    Fail "Projeto nao encontrado em $Project"
}
if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) {
    Fail "Clone autenticado do relay nao encontrado em $Repo"
}

$git = (Get-Command git.exe -ErrorAction Stop).Source
$ps  = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"

$origin = (& $git -C $Repo remote get-url origin 2>$null | Out-String).Trim()
if ($origin -notmatch 'ProjetosCosaNostra[/\\]BlackVault_Sentinel') {
    Fail "Origin inesperado no clone do relay: $origin"
}

New-Item -ItemType Directory -Force -Path $Base,$LogDir | Out-Null

& $git -C $Repo fetch origin $Branch
if ($LASTEXITCODE -ne 0) { Fail 'git fetch falhou' }
& $git -C $Repo checkout $Branch
if ($LASTEXITCODE -ne 0) { Fail 'git checkout falhou' }
& $git -C $Repo reset --hard "origin/$Branch"
if ($LASTEXITCODE -ne 0) { Fail 'git reset falhou' }

if (-not (Test-Path -LiteralPath $Client)) {
    Fail "Cliente do relay nao encontrado: $Client"
}

$runnerBody = @"
`$ErrorActionPreference = 'Stop'
`$Client = '$Client'
`$Base = '$Base'
`$LogDir = '$LogDir'
New-Item -ItemType Directory -Force -Path `$LogDir | Out-Null
`$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
`$log = Join-Path `$LogDir ("relay_v3_" + `$stamp + ".log")
try {
    & '$ps' -NoProfile -ExecutionPolicy Bypass -File `$Client *>> `$log
    if (`$LASTEXITCODE -ne 0) { throw "PROJECT_RELAY_CLIENT falhou com codigo `$LASTEXITCODE" }
    Set-Content -LiteralPath (Join-Path `$Base 'LAST_RUN_OK.txt') -Value (Get-Date -Format o) -Encoding UTF8
}
catch {
    @((Get-Date -Format o), `$_.Exception.ToString()) |
        Set-Content -LiteralPath (Join-Path `$Base 'LAST_RUN_ERROR.txt') -Encoding UTF8
    throw
}
"@
[IO.File]::WriteAllText($Runner,$runnerBody,[Text.UTF8Encoding]::new($false))

$vbsBody = @"
Set sh = CreateObject("WScript.Shell")
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""$Runner""", 0, False
"@
[IO.File]::WriteAllText($Hidden,$vbsBody,[Text.UTF8Encoding]::new($false))

$taskCmd = 'wscript.exe "' + $Hidden + '"'
& schtasks.exe /Create /TN $TaskName /SC MINUTE /MO 5 /TR $taskCmd /F | Out-Null
if ($LASTEXITCODE -ne 0) { Fail "Nao foi possivel criar/atualizar a tarefa $TaskName" }

& $ps -NoProfile -ExecutionPolicy Bypass -File $Runner
if ($LASTEXITCODE -ne 0) {
    Fail "Primeira execucao falhou. Verifique $(Join-Path $Base 'LAST_RUN_ERROR.txt')"
}

Write-Host ''
Write-Host 'BLACKGOLD ORCAMENTO RELAY V3 ATIVO' -ForegroundColor Green
Write-Host "Projeto protegido: $Project" -ForegroundColor Cyan
Write-Host "Tarefa: $TaskName (a cada 5 minutos, oculta)" -ForegroundColor Cyan
Write-Host 'Relay: arquivos do projeto; nenhum comando remoto recebido do GitHub.' -ForegroundColor Yellow
