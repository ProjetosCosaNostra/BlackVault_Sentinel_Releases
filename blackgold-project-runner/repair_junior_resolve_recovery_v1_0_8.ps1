$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$ProgressPreference = 'SilentlyContinue'

$Base = Join-Path $env:LOCALAPPDATA 'BlackGoldProjectRunner'
$RunnerPath = Join-Path $Base 'runner.ps1'
$RunnerTemp = Join-Path $Base 'runner.v1_0_8.clean.ps1'
$RecoveryScript = Join-Path $Base 'junior-recovery-apply.ps1'
$TaskName = 'BlackGold_Project_Runner_V1'

$RunnerUrl = 'https://raw.githubusercontent.com/ProjetosCosaNostra/BlackVault_Sentinel_Releases/c87346c90c269356c8ad5af850a25c21d6fc102f/blackgold-project-runner/runner.ps1'

$LocalRoot = 'E:\Junior_Resolve__RECOVERY_A17_20260917'
$RecoveryRef = 'backup/jr-recovered-r63f-android-parser-fixed-20260921'
$SnapshotRoot = 'E:\Junior_Resolve__RECOVERY_SNAPSHOTS'

function Invoke-NativeChecked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $oldPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = @(
            & $FilePath @Arguments 2>&1
        )
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $oldPreference
    }

    foreach ($line in $output) {
        Write-Host ([string]$line)
    }

    if ($code -ne 0) {
        throw "NATIVE_FAILED_$code : $FilePath $($Arguments -join ' ')"
    }
}

if (-not (Test-Path -LiteralPath $Base)) {
    throw "BLACKGOLD_PROJECT_RUNNER_NOT_INSTALLED: $Base"
}

if (-not (Test-Path -LiteralPath (Join-Path $LocalRoot '.git'))) {
    throw "JUNIOR_RECOVERY_LOCAL_GIT_NOT_FOUND: $LocalRoot"
}

Import-Module ScheduledTasks -ErrorAction Stop
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Write-Host ''
Write-Host '[1/4] Restaurando BlackGold Project Runner limpo V1.0.8...' -ForegroundColor Cyan

Invoke-WebRequest -UseBasicParsing -Uri $RunnerUrl -OutFile $RunnerTemp

$runnerText = Get-Content -LiteralPath $RunnerTemp -Raw

if ($runnerText -notmatch "RunnerVersion\s*=\s*'1\.0\.8'") {
    throw 'RUNNER_V1_0_8_VERSION_MISMATCH'
}

if ($runnerText -match 'Invoke-Expression|iex\s') {
    throw 'RUNNER_V1_0_8_ARBITRARY_EXECUTION_REJECTED'
}

if (([regex]::Matches($runnerText,'Set-StrictMode -Version Latest')).Count -ne 1) {
    throw 'RUNNER_V1_0_8_DUPLICATED_STRICTMODE'
}

if (([regex]::Matches($runnerText,'function Invoke-Job')).Count -ne 1) {
    throw 'RUNNER_V1_0_8_DUPLICATED_INVOKE_JOB'
}

if ($runnerText -notmatch 'JUNIOR_RESOLVE_DIRECT_LAUNCH_BLOCKED_USE_RECOVERY') {
    throw 'RUNNER_V1_0_8_MISSING_JUNIOR_STALE_LAUNCH_GUARD'
}

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $RunnerTemp,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    throw ("RUNNER_V1_0_8_PARSE_FAILED: " + $messages)
}

Move-Item -LiteralPath $RunnerTemp -Destination $RunnerPath -Force

Write-Host '[2/4] Buscando checkpoint recovery congelado...' -ForegroundColor Cyan

$git = (Get-Command git.exe -ErrorAction Stop).Source
$remoteRef = 'refs/remotes/origin/' + $RecoveryRef
$refspec = '+refs/heads/' + $RecoveryRef + ':' + $remoteRef

Invoke-NativeChecked -FilePath $git -Arguments @(
    '-C',
    $LocalRoot,
    'fetch',
    '--force',
    'origin',
    $refspec
)

$oldPreference = $ErrorActionPreference
try {
    $ErrorActionPreference = 'Continue'
    $objectSpec = $remoteRef + ':scripts/recovery/Apply-Recovery-To-LocalAndroid.ps1'
    $scriptLines = @(
        & $git -C $LocalRoot show $objectSpec 2>$null
    )
    $showCode = $LASTEXITCODE
}
finally {
    $ErrorActionPreference = $oldPreference
}

if ($showCode -ne 0) {
    throw "RECOVERY_SCRIPT_FETCH_FAILED_$showCode"
}

$scriptText = $scriptLines -join [Environment]::NewLine

if (([regex]::Matches($scriptText,'Set-StrictMode -Version Latest')).Count -ne 1) {
    throw 'RECOVERY_SCRIPT_DUPLICATED_OR_MISSING'
}

if (([regex]::Matches($scriptText,'\[string\]\$RecoveryRef')).Count -ne 1) {
    throw 'RECOVERY_SCRIPT_RECOVERY_REF_INVALID'
}

if (([regex]::Matches($scriptText,'recovery-android-receipt\.json')).Count -ne 1) {
    throw 'RECOVERY_SCRIPT_RECEIPT_BLOCK_INVALID'
}

[IO.File]::WriteAllText(
    $RecoveryScript,
    $scriptText,
    [Text.UTF8Encoding]::new($false)
)

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile(
    $RecoveryScript,
    [ref]$tokens,
    [ref]$parseErrors
) | Out-Null

if ($parseErrors.Count -gt 0) {
    $messages = ($parseErrors | ForEach-Object { $_.Message }) -join ' | '
    throw ("RECOVERY_SCRIPT_PARSE_FAILED: " + $messages)
}

Write-Host '[3/4] Aplicando recovery validada no Android...' -ForegroundColor Cyan
Write-Host "Checkpoint: $RecoveryRef" -ForegroundColor Yellow

$powershell = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$psArgs = @(
    '-NoLogo',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $RecoveryScript,
    '-LocalRoot',
    $LocalRoot,
    '-RecoveryRef',
    $RecoveryRef,
    '-SnapshotRoot',
    $SnapshotRoot
)

& $powershell @psArgs
$applyCode = $LASTEXITCODE

if ($applyCode -ne 0) {
    throw "JUNIOR_RECOVERY_APPLY_FAILED_$applyCode"
}

$receiptFile = Get-ChildItem -LiteralPath $SnapshotRoot -Filter 'recovery-android-receipt.json' -File -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTimeUtc -Descending |
    Select-Object -First 1

if (-not $receiptFile) {
    throw 'JUNIOR_RECOVERY_RECEIPT_NOT_FOUND'
}

$receipt = Get-Content -LiteralPath $receiptFile.FullName -Raw | ConvertFrom-Json

if ([string]$receipt.RecoveryRef -ne $RecoveryRef) {
    throw "JUNIOR_RECOVERY_RECEIPT_REF_MISMATCH: $($receipt.RecoveryRef)"
}

if ([string]$receipt.AndroidInstallDebug -ne 'PASS') {
    throw 'JUNIOR_RECOVERY_ANDROID_INSTALL_NOT_PASS'
}

Write-Host '[4/4] Recovery instalada. Reativando automacao...' -ForegroundColor Cyan
Start-ScheduledTask -TaskName $TaskName

Write-Host ''
Write-Host 'JUNIOR RESOLVE RECOVERY RESTAURADA NO EMULADOR' -ForegroundColor Green
Write-Host "Recovery: $($receipt.RecoveryRef)" -ForegroundColor Green
Write-Host "Commit: $($receipt.RecoveryCommit)" -ForegroundColor Green
Write-Host "Package: $($receipt.PackageName)" -ForegroundColor Green
Write-Host "Snapshot: $($receipt.Snapshot)" -ForegroundColor Cyan
Write-Host "Screenshot: $($receipt.Screenshot)" -ForegroundColor Cyan
Write-Host ''
Write-Host 'APK antigo nao foi usado como fonte desta aprovacao.' -ForegroundColor Yellow
Write-Host 'Main/Producao/Play Store nao foram alterados.' -ForegroundColor Yellow
