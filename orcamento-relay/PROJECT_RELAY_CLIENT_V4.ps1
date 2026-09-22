$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ProjectRoot = 'E:\Orcamento_no_Ponto'
$Branch = 'orcamento-no-ponto-relay'
$Repo = Join-Path $env:LOCALAPPDATA 'BlackGold\OrcamentoRelay\repo'
$Relay = Join-Path $Repo 'relay\Orcamento_no_Ponto'
$Snapshot = Join-Path $Relay 'snapshot'
$PatchRoot = Join-Path $Relay 'patches'
$Pointer = Join-Path $Relay 'CURRENT_PATCH.txt'
$State = Join-Path $env:LOCALAPPDATA 'BlackGold\OrcamentoRelay\state'
$LastPatchFile = Join-Path $State 'last_patch.txt'
$Git = (Get-Command git.exe -ErrorAction Stop).Source

New-Item -ItemType Directory -Force -Path $State | Out-Null

function CopyTreeSafe([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) { return }

    $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    [IO.Directory]::CreateDirectory($Destination) | Out-Null

    $files = @(Get-ChildItem -LiteralPath $Source -Recurse -File -Force)
    foreach ($file in $files) {
        $relative = $file.FullName.Substring($sourceRoot.Length).TrimStart('\')
        $target = Join-Path $Destination $relative
        $targetDir = Split-Path -Parent $target
        if ($targetDir) {
            [IO.Directory]::CreateDirectory($targetDir) | Out-Null
        }
        [IO.File]::Copy($file.FullName, $target, $true)
    }
}

function Get-TextRegionHash([string]$Text, [string]$StartMarker, [string]$EndMarker) {
    $start = $Text.IndexOf($StartMarker, [StringComparison]::Ordinal)
    if ($start -lt 0) {
        throw "Visual guard: marcador inicial nao encontrado: $StartMarker"
    }
    $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [StringComparison]::Ordinal)
    if ($end -lt 0) {
        throw "Visual guard: marcador final nao encontrado: $EndMarker"
    }
    $region = $Text.Substring($start, $end - $start)
    $bytes = [Text.Encoding]::UTF8.GetBytes($region)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Assert-ApprovedMainActivityRegionsUnchanged([string]$CurrentPath, [string]$PatchPath) {
    $current = Get-Content -LiteralPath $CurrentPath -Raw
    $patch = Get-Content -LiteralPath $PatchPath -Raw
    $regions = @(
        @('    private final class HomeApprovedView extends View {',
          '    private void showHomeCanvasNative() {'),
        @('    private void showHomeAuthorityExact() {',
          '    private final class ApprovedScreenView extends View {'),
        @('    private final class ApprovedScreenView extends View {',
          '    private void showApprovedCanvasScreen(int mode){')
    )
    foreach ($pair in $regions) {
        $before = Get-TextRegionHash $current $pair[0] $pair[1]
        $after = Get-TextRegionHash $patch $pair[0] $pair[1]
        if ($before -ne $after) {
            throw "Patch bloqueado: tentou alterar regiao visual aprovada: $($pair[0].Trim())"
        }
    }
}

function Sync-RelayRepo {
    & $Git -C $Repo config core.longpaths true
    if ($LASTEXITCODE -ne 0) { throw 'GIT_LONGPATHS_CONFIG_FAILED' }

    & $Git -C $Repo fetch origin $Branch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'GIT_FETCH_FAILED' }

    & $Git -C $Repo checkout $Branch | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'GIT_CHECKOUT_FAILED' }

    # Dedicated relay clone: uncommitted generated state means an interrupted sync.
    & $Git -C $Repo reset --hard ("origin/" + $Branch) | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'GIT_RESET_FAILED' }

    & $Git -C $Repo clean -fd -- 'relay/Orcamento_no_Ponto/snapshot' 'relay/Orcamento_no_Ponto/acks' 'relay/Orcamento_no_Ponto/heartbeats' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'GIT_CLEAN_FAILED' }
}

Sync-RelayRepo

$patchId = ''
if (Test-Path -LiteralPath $Pointer) {
    $patchId = (Get-Content -LiteralPath $Pointer -Raw).Trim()
}

$lastPatch = ''
if (Test-Path -LiteralPath $LastPatchFile) {
    $lastPatch = (Get-Content -LiteralPath $LastPatchFile -Raw).Trim()
}

if ($patchId -and $lastPatch -eq $patchId) {
    $previousAck = Join-Path $Relay ("acks\" + $patchId + ".txt")
    if (Test-Path -LiteralPath $previousAck) {
        $ackText = Get-Content -LiteralPath $previousAck -Raw
        if ($ackText -match '(?m)^status=ROLLED_BACK\s*$') {
            $lastPatch = ''
        }
    }
}

if ($patchId -and $patchId -ne $lastPatch) {
    $PatchDir = Join-Path $PatchRoot $patchId
    if (-not (Test-Path -LiteralPath $PatchDir)) {
        throw "Patch nao encontrado: $patchId"
    }

    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Backup = Join-Path $ProjectRoot ('99_Backups\RELAY_' + $stamp)
    $backupFilesDir = Join-Path $Backup 'files'
    $buildLog = Join-Path $Backup 'relay_build.log'
    $lintLog = Join-Path $Backup 'relay_lint.log'
    New-Item -ItemType Directory -Force -Path $backupFilesDir | Out-Null

    $appliedRecords = @()
    $backupMap = New-Object System.Collections.Generic.List[string]
    $patchStatus = 'PENDING'
    $patchError = ''
    $lintCode = -999
    $fileIndex = 0

    try {
        $files = @(Get-ChildItem -LiteralPath $PatchDir -Recurse -File)
        foreach ($file in $files) {
            $relative = $file.FullName.Substring($PatchDir.Length).TrimStart('\')
            $allowed = $relative.StartsWith(
                '01_Android_App\orcamento_no_ponto\app\src\main\',
                [StringComparison]::OrdinalIgnoreCase
            )
            if (-not $allowed) {
                throw "Patch bloqueado fora do escopo: $relative"
            }

            $leaf = [IO.Path]::GetFileName($relative)
            $isApprovedAsset = (
                $relative -match '(?i)\\res\\' -and (
                    $leaf -like 'authority_*' -or
                    $leaf -like '*_approved_*' -or
                    $leaf -like 'ui_*' -or
                    $leaf -like 'exact_*'
                )
            )
            if ($isApprovedAsset) {
                throw "Patch bloqueado: asset visual aprovado esta congelado: $relative"
            }

            $destination = Join-Path $ProjectRoot $relative
            $destinationFull = [IO.Path]::GetFullPath($destination)
            $rootFull = [IO.Path]::GetFullPath($ProjectRoot + '\')
            if (-not $destinationFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Patch tentou sair do projeto: $relative"
            }

            if ($leaf -ieq 'MainActivity.java' -and (Test-Path -LiteralPath $destination)) {
                Assert-ApprovedMainActivityRegionsUnchanged $destination $file.FullName
            }

            $fileIndex++
            $existed = Test-Path -LiteralPath $destination
            $backupFile = ''
            if ($existed) {
                $backupFile = Join-Path $backupFilesDir (('{0:D3}.bak' -f $fileIndex))
                Copy-Item -LiteralPath $destination -Destination $backupFile -Force
            }
            $backupMap.Add(('{0:D3}|{1}|{2}' -f $fileIndex, $relative, $existed)) | Out-Null

            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
            Copy-Item -LiteralPath $file.FullName -Destination $destination -Force

            $appliedRecords += [pscustomobject]@{
                Destination = $destination
                Backup = $backupFile
                Existed = $existed
            }
        }

        $backupMap | Set-Content -LiteralPath (Join-Path $Backup 'backup_map.txt') -Encoding UTF8

        $androidProject = Join-Path $ProjectRoot '01_Android_App\orcamento_no_ponto'
        $gradlew = Join-Path $androidProject 'gradlew.bat'
        $gradleCommand = $null
        $buildCode = -1

        Push-Location $androidProject
        try {
            if (Test-Path -LiteralPath $gradlew) {
                & $gradlew --no-daemon :app:assembleDebug *> $buildLog
                $buildCode = $LASTEXITCODE
            }
            else {
                $gradleCommand = Get-Command gradle.bat -ErrorAction SilentlyContinue
                if (-not $gradleCommand) {
                    $gradleCommand = Get-Command gradle -ErrorAction SilentlyContinue
                }
                if (-not $gradleCommand) {
                    throw 'Gradle nao encontrado para validar o patch'
                }
                & $gradleCommand.Source --no-daemon :app:assembleDebug *> $buildLog
                $buildCode = $LASTEXITCODE
            }
        }
        finally {
            Pop-Location
        }

        if ($buildCode -ne 0) {
            throw "BUILD_FAILED_EXIT_$buildCode"
        }

        Push-Location $androidProject
        try {
            if (Test-Path -LiteralPath $gradlew) {
                & $gradlew --no-daemon :app:lintDebug *> $lintLog
                $lintCode = $LASTEXITCODE
            }
            elseif ($gradleCommand) {
                & $gradleCommand.Source --no-daemon :app:lintDebug *> $lintLog
                $lintCode = $LASTEXITCODE
            }
        }
        finally {
            Pop-Location
        }

        $patchStatus = 'APPLIED_BUILD_PASS'
    }
    catch {
        $patchError = $_.Exception.Message
        for ($index = $appliedRecords.Count - 1; $index -ge 0; $index--) {
            $record = $appliedRecords[$index]
            if ($record.Existed) {
                Copy-Item -LiteralPath $record.Backup -Destination $record.Destination -Force
            }
            else {
                Remove-Item -LiteralPath $record.Destination -Force -ErrorAction SilentlyContinue
            }
        }
        $patchStatus = 'ROLLED_BACK'
    }

    if ($patchStatus -eq 'APPLIED_BUILD_PASS') {
        Set-Content -LiteralPath $LastPatchFile -Value $patchId -Encoding UTF8
    }
    else {
        Remove-Item -LiteralPath $LastPatchFile -Force -ErrorAction SilentlyContinue
    }

    $ackDir = Join-Path $Relay 'acks'
    New-Item -ItemType Directory -Force -Path $ackDir | Out-Null
    $ackPath = Join-Path $ackDir ($patchId + '.txt')
    $safeError = ($patchError -replace '[\r\n]+', ' ')
    @(
        "patch=$patchId",
        "status=$patchStatus",
        "applied_at=$(Get-Date -Format o)",
        "backup=$Backup",
        "build_log=$buildLog",
        "lint_log=$lintLog",
        "lint_exit=$lintCode",
        "error=$safeError"
    ) | Set-Content -LiteralPath $ackPath -Encoding UTF8
}

Remove-Item -LiteralPath $Snapshot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $Snapshot | Out-Null

$srcBase = Join-Path $ProjectRoot '01_Android_App\orcamento_no_ponto\app\src\main'
$dstBase = Join-Path $Snapshot '01_Android_App\orcamento_no_ponto\app\src\main'

foreach ($sub in @('java', 'kotlin', 'assets', 'res')) {
    CopyTreeSafe (Join-Path $srcBase $sub) (Join-Path $dstBase $sub)
}

$manifest = Join-Path $srcBase 'AndroidManifest.xml'
if (Test-Path -LiteralPath $manifest) {
    New-Item -ItemType Directory -Force -Path $dstBase | Out-Null
    Copy-Item -LiteralPath $manifest -Destination (Join-Path $dstBase 'AndroidManifest.xml') -Force
}

$configs = @(
    '01_Android_App\orcamento_no_ponto\app\build.gradle.kts',
    '01_Android_App\orcamento_no_ponto\app\build.gradle',
    '01_Android_App\orcamento_no_ponto\build.gradle.kts',
    '01_Android_App\orcamento_no_ponto\build.gradle',
    '01_Android_App\orcamento_no_ponto\settings.gradle.kts',
    '01_Android_App\orcamento_no_ponto\settings.gradle',
    '01_Android_App\orcamento_no_ponto\gradle.properties'
)
foreach ($relativeConfig in $configs) {
    $sourceConfig = Join-Path $ProjectRoot $relativeConfig
    if (Test-Path -LiteralPath $sourceConfig) {
        $destinationConfig = Join-Path $Snapshot $relativeConfig
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destinationConfig) | Out-Null
        Copy-Item -LiteralPath $sourceConfig -Destination $destinationConfig -Force
    }
}

$ecosystemDir = Join-Path $ProjectRoot '03_Ecossistema'
if (Test-Path -LiteralPath $ecosystemDir) {
    CopyTreeSafe $ecosystemDir (Join-Path $Snapshot '03_Ecossistema')
}

$visualHashFile = Join-Path $Snapshot '_VISUAL_HASHES.txt'
$visualAssets = @()
$resRoot = Join-Path $srcBase 'res'
if (Test-Path -LiteralPath $resRoot) {
    $visualAssets = @(Get-ChildItem -LiteralPath $resRoot -Recurse -File | Where-Object {
        $_.Name -like 'authority_*' -or
        $_.Name -like '*_approved_*' -or
        $_.Name -like 'ui_*' -or
        $_.Name -like 'exact_*'
    } | Sort-Object FullName)

    $hashLines = foreach ($asset in $visualAssets) {
        $relativeAsset = $asset.FullName.Substring($srcBase.Length).TrimStart('\')
        $hash = (Get-FileHash -LiteralPath $asset.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        "$relativeAsset|$hash"
    }
    @($hashLines) | Set-Content -LiteralPath $visualHashFile -Encoding UTF8
}

$visualBaselineStatus = 'MISSING'
$visualDriftCount = 0
$visualBaselineFile = Join-Path $Relay 'validation\VISUAL_BASELINE_APPROVED_V1.txt'
if (Test-Path -LiteralPath $visualBaselineFile) {
    $baselineLines = @(Get-Content -LiteralPath $visualBaselineFile | Where-Object {
        $_ -and -not $_.StartsWith('#')
    } | ForEach-Object { $_.Trim() })
    $currentLines = @()
    if (Test-Path -LiteralPath $visualHashFile) {
        $currentLines = @(Get-Content -LiteralPath $visualHashFile | Where-Object { $_ } | ForEach-Object { $_.Trim() })
    }
    $visualDriftCount = @(Compare-Object -ReferenceObject $baselineLines -DifferenceObject $currentLines).Count
    $visualBaselineStatus = if ($visualDriftCount -eq 0) { 'PASS' } else { 'DRIFT' }
}

@(
    'status=ONLINE',
    "synced_at=$(Get-Date -Format o)",
    "project=$ProjectRoot",
    'home_v07=FROZEN',
    "visual_assets_hashed=$($visualAssets.Count)",
    "visual_baseline_status=$visualBaselineStatus",
    "visual_drift_count=$visualDriftCount",
    'publication=NO'
) | Set-Content -LiteralPath (Join-Path $Snapshot '_STATUS.txt') -Encoding UTF8

$gradleConfig = Join-Path $ProjectRoot '01_Android_App\orcamento_no_ponto\app\build.gradle.kts'
$gradleText = if (Test-Path -LiteralPath $gradleConfig) {
    Get-Content -LiteralPath $gradleConfig -Raw
} else {
    ''
}

$targetSdk = 0
if ($gradleText -match 'targetSdk\s*=\s*(\d+)') {
    $targetSdk = [int]$Matches[1]
}
$billingVersion = ''
if ($gradleText -match 'com\.android\.billingclient:billing:([0-9.]+)') {
    $billingVersion = $Matches[1]
}

$currentAckStatus = 'NONE'
$currentLintExit = $null
if ($patchId) {
    $currentAck = Join-Path (Join-Path $Relay 'acks') ($patchId + '.txt')
    if (Test-Path -LiteralPath $currentAck) {
        $currentAckText = Get-Content -LiteralPath $currentAck -Raw
        if ($currentAckText -match '(?m)^status=(.+)$') {
            $currentAckStatus = $Matches[1].Trim()
        }
        if ($currentAckText -match '(?m)^lint_exit=(-?\d+)$') {
            $currentLintExit = [int]$Matches[1]
        }
    }
}

$gateReasons = New-Object System.Collections.Generic.List[string]
if ($targetSdk -lt 36) { $gateReasons.Add('TARGET_SDK_LT_36') | Out-Null }
if ($visualBaselineStatus -ne 'PASS') { $gateReasons.Add('VISUAL_BASELINE_NOT_PASS') | Out-Null }
if ($patchId -and $currentAckStatus -ne 'APPLIED_BUILD_PASS') { $gateReasons.Add('CURRENT_PATCH_NOT_BUILD_PASS') | Out-Null }
if ($billingVersion -ne '9.1.0') { $gateReasons.Add('BILLING_VERSION_UNEXPECTED') | Out-Null }

$technicalStatus = if ($gateReasons.Count -eq 0) { 'TECHNICAL_PASS' } else { 'BLOCKED' }
$gate = [ordered]@{
    schema = 'blackgold.android.delivery-gate.v1'
    generated_at = (Get-Date -Format o)
    project = $ProjectRoot
    target_sdk = $targetSdk
    billing_version = $billingVersion
    visual_baseline_status = $visualBaselineStatus
    visual_drift_count = $visualDriftCount
    current_patch = $patchId
    current_patch_status = $currentAckStatus
    lint_exit = $currentLintExit
    technical_status = $technicalStatus
    blockers = @($gateReasons)
    publication = 'NO'
}
$gate | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Snapshot '_DELIVERY_GATE_V1.json') -Encoding UTF8

$heartbeatDir = Join-Path $Relay 'heartbeats'
New-Item -ItemType Directory -Force -Path $heartbeatDir | Out-Null
@(
    'status=ONLINE',
    "device=$env:COMPUTERNAME",
    "user=$env:USERNAME",
    "time=$(Get-Date -Format o)",
    "project=$ProjectRoot",
    'relay_version=4',
    "current_patch=$patchId",
    "current_patch_status=$currentAckStatus",
    "visual_baseline_status=$visualBaselineStatus",
    "visual_drift_count=$visualDriftCount"
) | Set-Content -LiteralPath (Join-Path $heartbeatDir 'FELIPE.txt') -Encoding UTF8


# BLACKGOLD_RUNTIME_RECOVERY_V1
# Operacao fechada: nunca executa comandos vindos do GitHub.
# Um request ID apenas autoriza esta rotina fixa a compilar, abrir o AVD exclusivo,
# instalar o APK de debug, iniciar a MainActivity e devolver evidencias.
$runtimeDir = Join-Path $Relay 'runtime'
$runtimeRequestFile = Join-Path $runtimeDir 'REQUEST.txt'
$lastRuntimeRequestFile = Join-Path $State 'last_runtime_request.txt'
New-Item -ItemType Directory -Force -Path $runtimeDir | Out-Null

$runtimeRequestId = ''
if (Test-Path -LiteralPath $runtimeRequestFile) {
    $runtimeRequestId = (Get-Content -LiteralPath $runtimeRequestFile -Raw).Trim()
}
$lastRuntimeRequestId = ''
if (Test-Path -LiteralPath $lastRuntimeRequestFile) {
    $lastRuntimeRequestId = (Get-Content -LiteralPath $lastRuntimeRequestFile -Raw).Trim()
}

if ($runtimeRequestId -and $runtimeRequestId -ne $lastRuntimeRequestId) {
    $targetAvd = 'Orcamento_no_Ponto_API35'
    $targetPackage = 'br.com.lafamigliaplayworks.orcamentonoponto'
    $targetActivity = $targetPackage + '/.MainActivity'
    $safeRequestId = ($runtimeRequestId -replace '[^A-Za-z0-9_.-]', '_')
    $resultPath = Join-Path $runtimeDir ('RESULT_' + $safeRequestId + '.txt')
    $buildResultLog = Join-Path $runtimeDir ('BUILD_' + $safeRequestId + '.log')
    $runtimeLog = Join-Path $runtimeDir ('LOGCAT_' + $safeRequestId + '.log')
    $runtimeShot = Join-Path $runtimeDir ('SCREEN_' + $safeRequestId + '.png')
    $runtimeStatus = 'PENDING'
    $runtimeError = ''
    $runtimeSerial = ''
    $runtimeBoot = ''
    $runtimePid = ''
    $runtimeForeground = ''

    try {
        $androidProject = Join-Path $ProjectRoot '01_Android_App\orcamento_no_ponto'
        $gradlew = Join-Path $androidProject 'gradlew.bat'
        $apk = Join-Path $androidProject 'app\build\outputs\apk\debug\app-debug.apk'
        $gradleCommand = $null
        $buildCode = -1

        Push-Location $androidProject
        try {
            if (Test-Path -LiteralPath $gradlew) {
                & $gradlew --no-daemon :app:assembleDebug *> $buildResultLog
                $buildCode = $LASTEXITCODE
            }
            else {
                $gradleCommand = Get-Command gradle.bat -ErrorAction SilentlyContinue
                if (-not $gradleCommand) {
                    $gradleCommand = Get-Command gradle -ErrorAction SilentlyContinue
                }
                if (-not $gradleCommand) {
                    throw 'Gradle nao encontrado para runtime recovery'
                }
                & $gradleCommand.Source --no-daemon :app:assembleDebug *> $buildResultLog
                $buildCode = $LASTEXITCODE
            }
        }
        finally {
            Pop-Location
        }

        if ($buildCode -ne 0) {
            throw "RUNTIME_BUILD_FAILED_EXIT_$buildCode"
        }
        if (-not (Test-Path -LiteralPath $apk)) {
            throw "APK_DEBUG_NAO_ENCONTRADO: $apk"
        }

        $adbCandidates = New-Object System.Collections.Generic.List[string]
        if ($env:ANDROID_SDK_ROOT) {
            $adbCandidates.Add((Join-Path $env:ANDROID_SDK_ROOT 'platform-tools\adb.exe')) | Out-Null
        }
        if ($env:ANDROID_HOME) {
            $adbCandidates.Add((Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe')) | Out-Null
        }
        $adbCandidates.Add((Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')) | Out-Null

        $adbPath = $null
        foreach ($candidate in $adbCandidates) {
            if ($candidate -and (Test-Path -LiteralPath $candidate)) {
                $adbPath = $candidate
                break
            }
        }
        if (-not $adbPath) {
            $adbCommand = Get-Command adb.exe -ErrorAction SilentlyContinue
            if (-not $adbCommand) { $adbCommand = Get-Command adb -ErrorAction SilentlyContinue }
            if ($adbCommand) { $adbPath = $adbCommand.Source }
        }
        if (-not $adbPath) {
            throw 'ADB_NAO_ENCONTRADO'
        }

        $emulatorCandidates = New-Object System.Collections.Generic.List[string]
        if ($env:ANDROID_SDK_ROOT) {
            $emulatorCandidates.Add((Join-Path $env:ANDROID_SDK_ROOT 'emulator\emulator.exe')) | Out-Null
        }
        if ($env:ANDROID_HOME) {
            $emulatorCandidates.Add((Join-Path $env:ANDROID_HOME 'emulator\emulator.exe')) | Out-Null
        }
        $emulatorCandidates.Add((Join-Path $env:LOCALAPPDATA 'Android\Sdk\emulator\emulator.exe')) | Out-Null

        $emulatorPath = $null
        foreach ($candidate in $emulatorCandidates) {
            if ($candidate -and (Test-Path -LiteralPath $candidate)) {
                $emulatorPath = $candidate
                break
            }
        }

        function Get-OrcamentoTargetSerial([string]$Adb, [string]$ExpectedAvd) {
            $deviceLines = @(& $Adb devices 2>$null)
            foreach ($line in $deviceLines) {
                if ($line -match '^(emulator-\d+)\s+device\s*    & $Git add -- 'relay/Orcamento_no_Ponto'
    $changes = & $Git status --porcelain -- 'relay/Orcamento_no_Ponto'
    if ($changes) {
        & $Git config user.name 'BlackGold Orçamento Relay'
        & $Git config user.email 'blackgold-relay@local.invalid'
        & $Git commit -m ("relay: sync Orçamento no Ponto " + (Get-Date -Format 'yyyyMMdd-HHmmss')) | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'GIT_COMMIT_FAILED' }
        & $Git pull --rebase origin $Branch | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'GIT_REBASE_FAILED' }
        & $Git push origin $Branch | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'GIT_PUSH_FAILED' }
    }
}
finally {
    Pop-Location
}
) {
                    $serial = $Matches[1]
                    $avdLines = @(& $Adb -s $serial emu avd name 2>$null)
                    $avdName = ''
                    foreach ($avdLine in $avdLines) {
                        $trimmed = ('' + $avdLine).Trim()
                        if ($trimmed -and $trimmed -ne 'OK') {
                            $avdName = $trimmed
                            break
                        }
                    }
                    if ($avdName -eq $ExpectedAvd) {
                        return $serial
                    }
                }
            }
            return ''
        }

        & $adbPath start-server | Out-Null
        $runtimeSerial = Get-OrcamentoTargetSerial $adbPath $targetAvd

        if (-not $runtimeSerial) {
            if (-not $emulatorPath) {
                throw 'EMULATOR_EXE_NAO_ENCONTRADO'
            }

            Start-Process -FilePath $emulatorPath -ArgumentList @(
                '-avd', $targetAvd,
                '-no-snapshot-load'
            ) | Out-Null

            for ($i = 0; $i -lt 90 -and -not $runtimeSerial; $i++) {
                Start-Sleep -Seconds 2
                $runtimeSerial = Get-OrcamentoTargetSerial $adbPath $targetAvd
            }
        }

        if (-not $runtimeSerial) {
            throw "AVD_ALVO_NAO_FICOU_ONLINE: $targetAvd"
        }

        for ($i = 0; $i -lt 90; $i++) {
            $runtimeBoot = ((& $adbPath -s $runtimeSerial shell getprop sys.boot_completed 2>$null) | Out-String).Trim()
            if ($runtimeBoot -eq '1') { break }
            Start-Sleep -Seconds 2
        }
        if ($runtimeBoot -ne '1') {
            throw "AVD_ALVO_NAO_COMPLETOU_BOOT: $runtimeSerial"
        }

        $installOutput = ((& $adbPath -s $runtimeSerial install -r $apk 2>&1) | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or $installOutput -notmatch 'Success') {
            throw "ADB_INSTALL_FAILED: $installOutput"
        }

        & $adbPath -s $runtimeSerial logcat -c | Out-Null
        & $adbPath -s $runtimeSerial shell am force-stop $targetPackage | Out-Null
        $startOutput = ((& $adbPath -s $runtimeSerial shell am start -W -n $targetActivity 2>&1) | Out-String).Trim()
        Start-Sleep -Seconds 4

        $runtimePid = ((& $adbPath -s $runtimeSerial shell pidof $targetPackage 2>$null) | Out-String).Trim()
        $activityDump = ((& $adbPath -s $runtimeSerial shell dumpsys activity activities 2>$null) | Out-String)
        if ($activityDump -match [regex]::Escape($targetPackage + '/.MainActivity')) {
            $runtimeForeground = 'YES'
        } else {
            $runtimeForeground = 'NO'
        }

        ((& $adbPath -s $runtimeSerial logcat -d -v threadtime 2>&1) | Out-String) |
            Set-Content -LiteralPath $runtimeLog -Encoding UTF8

        & $adbPath -s $runtimeSerial shell screencap -p /sdcard/orcamento_runtime_recovery.png | Out-Null
        & $adbPath -s $runtimeSerial pull /sdcard/orcamento_runtime_recovery.png $runtimeShot | Out-Null

        if (-not $runtimePid) {
            throw 'APP_PROCESS_NOT_ALIVE'
        }
        if ($runtimeForeground -ne 'YES') {
            throw 'MAIN_ACTIVITY_NOT_FOREGROUND'
        }

        $runtimeStatus = 'PASS'
    }
    catch {
        $runtimeStatus = 'FAILED'
        $runtimeError = ($_.Exception.Message -replace '[\r\n]+', ' ')
        if ($runtimeSerial) {
            try {
                ((& $adbPath -s $runtimeSerial logcat -d -v threadtime 2>&1) | Out-String) |
                    Set-Content -LiteralPath $runtimeLog -Encoding UTF8
            } catch {}
        }
    }
    finally {
        @(
            "request=$runtimeRequestId",
            "status=$runtimeStatus",
            "time=$(Get-Date -Format o)",
            "project=$ProjectRoot",
            "target_avd=$targetAvd",
            "serial=$runtimeSerial",
            "boot_completed=$runtimeBoot",
            "package=$targetPackage",
            "pid=$runtimePid",
            "foreground=$runtimeForeground",
            "build_log=$buildResultLog",
            "logcat=$runtimeLog",
            "screenshot=$runtimeShot",
            "error=$runtimeError"
        ) | Set-Content -LiteralPath $resultPath -Encoding UTF8

        Set-Content -LiteralPath $lastRuntimeRequestFile -Value $runtimeRequestId -Encoding UTF8
    }
}
# /BLACKGOLD_RUNTIME_RECOVERY_V1

Push-Location $Repo
try {
    & $Git add -- 'relay/Orcamento_no_Ponto'
    $changes = & $Git status --porcelain -- 'relay/Orcamento_no_Ponto'
    if ($changes) {
        & $Git config user.name 'BlackGold Orçamento Relay'
        & $Git config user.email 'blackgold-relay@local.invalid'
        & $Git commit -m ("relay: sync Orçamento no Ponto " + (Get-Date -Format 'yyyyMMdd-HHmmss')) | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'GIT_COMMIT_FAILED' }
        & $Git pull --rebase origin $Branch | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'GIT_REBASE_FAILED' }
        & $Git push origin $Branch | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'GIT_PUSH_FAILED' }
    }
}
finally {
    Pop-Location
}
