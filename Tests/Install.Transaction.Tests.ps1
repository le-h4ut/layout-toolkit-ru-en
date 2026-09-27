param([string]$TargetRoot = [IO.Path]::GetTempPath())
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'install.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | ForEach-Object Message | Out-String) }
$definitions = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)
Invoke-Expression (($definitions | ForEach-Object { $_.Extent.Text }) -join "`n")
$realStartupSetter = ${function:Set-StartupShortcut}
$realStateWriter = ${function:Write-InstallStateAtomic}
$realMetadataRestore = ${function:Restore-InstallMetadataBackup}
function Assert($Condition, $Message) { if (!$Condition) { throw "FAIL: $Message" } }
function Bytes([string]$Path) { return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) }
# All process/network actions are mocked; filesystem moves and shortcut/state writes are real.
function Start-ValidatedLayoutToolkit($Runtime, $TargetPath, $WorkDir) {
    $script:events += 'start'
    $backups = @(Get-ChildItem -LiteralPath (Split-Path -Parent $script:sourceTarget) -Directory | Where-Object Name -like '*.backup-*')
    $expectedBackups = if ($script:hasOld) { 1 } else { 0 }
    Assert ($backups.Count -eq $expectedBackups) 'backup exists until startup is validated'
    if ($script:fault -in @('start','recovery')) { throw 'simulated failed startup' }
    $child = [pscustomobject]@{ HasExited = $false }
    $child | Add-Member ScriptMethod Kill {
        if ($script:fault -eq 'stop') { throw 'simulated child stop failure' }
        $this.HasExited = $true; $script:events += 'stop'
    }
    $child | Add-Member ScriptMethod WaitForExit { param($Timeout) return $true }
    return $child
}
function Set-StartupShortcut($TargetPath) {
    $script:events += 'shortcut'
    & $realStartupSetter $TargetPath
    if ($script:fault -eq 'shortcut') { throw 'simulated shortcut failure after writing' }
}
function Write-InstallStateAtomic($Value) {
    $script:events += 'state'
    & $realStateWriter $Value
    if ($script:fault -in @('state','stop')) { throw 'simulated state failure after writing' }
}
function Restore-InstallMetadataBackup($Snapshot) {
    if ($script:fault -eq 'recovery') { throw 'simulated metadata restore failure' }
    & $realMetadataRestore $Snapshot
}
function Wait-PreviousInstance($SourcePath, $ProcessId) { }
function Resolve-InstallRuntime($PayloadPath, $WorkDir) { return 'C:\Test\AutoHotkey.exe' }
function Invoke-ReleaseHealthCheck($Runtime, $PayloadPath, $WorkDir) {
    $script:events += 'health'
    if ($script:fault -eq 'health') { throw 'simulated unhealthy release' }
}
function Invoke-RestMethod($Uri) { return $script:manifest }
function Invoke-WebRequest($Uri, $OutFile, [switch]$UseBasicParsing) { Copy-Item -LiteralPath $script:archive -Destination $OutFile }

$testRoot = Join-Path ([IO.Path]::GetFullPath($TargetRoot)) ('lt-transaction-tests-' + [guid]::NewGuid().ToString('N'))
$workRoot = Join-Path ([IO.Path]::GetTempPath()) ('lt-transaction-work-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot, $workRoot | Out-Null
try {
    foreach ($case in @('success','start','state','shortcut','health','hash','size','fresh-start','fresh-success','typo-start','typo-success','foreign','legacy-success','legacy-state','noautostart-success','foreignlegacy-success','recovery','stop')) {
        $caseRoot = Join-Path $testRoot $case
        $stateDir = Join-Path $caseRoot 'state'
        $statePath = Join-Path $stateDir 'install.json'
        $startupPath = Join-Path $caseRoot 'Layout Toolkit.lnk'
        $legacyStartupPath = Join-Path $caseRoot 'Layout Toolkit RU-EN.lnk'
        $work = Join-Path $workRoot $case
        $payload = Join-Path $work 'payload'
        New-Item -ItemType Directory -Path $stateDir, $payload | Out-Null
        $script:sourceTarget = Join-Path $caseRoot $(if ($case -like 'typo-*') { 'Layout Toolkir Ru En' } else { 'Layout Toolkit' })
        $target = Get-CanonicalUpdatePath $sourceTarget
        $script:hasOld = $case -notlike 'fresh-*'
        if ($hasOld) {
            New-Item -ItemType Directory -Path $sourceTarget | Out-Null
            [IO.File]::WriteAllText((Join-Path $sourceTarget 'Layout_Toolkit_RU_EN.ahk'), 'OLD_VERSION')
            [IO.File]::WriteAllText((Join-Path $sourceTarget 'Run_Layout_Toolkit.cmd'), '@echo off')
            [IO.File]::WriteAllText($statePath, (@{ schemaVersion=1; installPath=$sourceTarget; installedVersion='1.4.1'; autostart=$true } | ConvertTo-Json))
            [IO.File]::WriteAllText((Join-Path $stateDir 'autohotkey-path.txt'), 'OLD_RUNTIME')
            foreach ($path in @($startupPath, $legacyStartupPath)) {
                $link = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
                $link.TargetPath = Join-Path $sourceTarget 'Run_Layout_Toolkit.cmd'
                $link.WorkingDirectory = $sourceTarget
                $link.Save()
            }
        }
        if ($case -eq 'foreign') {
            $link = (New-Object -ComObject WScript.Shell).CreateShortcut($startupPath)
            $link.TargetPath = Join-Path $caseRoot 'another-copy.cmd'
            $link.Save()
        }
        if ($case -like 'legacy-*') { Remove-Item -LiteralPath $statePath }
        if ($case -eq 'foreignlegacy-success') {
            $link = (New-Object -ComObject WScript.Shell).CreateShortcut($legacyStartupPath)
            $link.TargetPath = Join-Path $caseRoot 'another-copy.cmd'
            $link.Save()
        }
        $saved = @{}
        foreach ($path in @($statePath,$startupPath,$legacyStartupPath,(Join-Path $stateDir 'autohotkey-path.txt'))) {
            if (Test-Path -LiteralPath $path) { $saved[$path] = Bytes $path }
        }
        [IO.File]::WriteAllText((Join-Path $payload 'Layout_Toolkit_RU_EN.ahk'), 'NEW_VERSION; LTHealth_Run()')
        [IO.File]::WriteAllText((Join-Path $payload 'Run_Layout_Toolkit.cmd'), '@echo off')
        New-Item -ItemType Directory -Path (Join-Path $payload 'Modules') | Out-Null
        [IO.File]::WriteAllText((Join-Path $payload 'Modules\HealthCheck.ahk'), '; protocol fixture')
        $script:archive = Join-Path $caseRoot 'release.zip'
        Compress-Archive -LiteralPath $payload -DestinationPath $archive
        $script:manifest = [pscustomobject]@{ schema_version=1; version='1.5.0'; channel='stable'; assets=@{windows=@{url='https://example.invalid/release.zip';size=(Get-Item $archive).Length;sha256=(Get-FileHash $archive).Hash}} }
        $script:fault = $case -replace '^(fresh|typo|legacy|noautostart|foreignlegacy)-',''
        $script:events = @()
        $failed = $false
        $failureMessage = ''
        try {
            if ($case -in @('health','hash','size','legacy-success')) {
                if ($case -eq 'hash') { $manifest.assets.windows.sha256 = '0' * 64 }
                if ($case -eq 'size') { $manifest.assets.windows.size++ }
                $InstallPath = if ($case -eq 'legacy-success') { '' } else { $sourceTarget }
                $Update = $true; $Uninstall = $false; $NoAutostart = $false; $WaitForPid = 0
                $manifestUrl = 'https://example.invalid/latest.json'
                Invoke-InstallerMain
            } else {
                Invoke-InstallTransaction $payload $sourceTarget $target 'C:\Test\AutoHotkey.exe' $work $manifest ($case -eq 'noautostart-success')
            }
        } catch { $failed = $true; $failureMessage = $_.Exception.Message; $failureException = $_.Exception }
        $success = $case -like '*success'
        Assert ($failed -ne $success) "$case expected result: $failureMessage"
        $backups = @(Get-ChildItem -LiteralPath $caseRoot -Directory | Where-Object Name -like '*.backup-*')
        if ($case -in @('recovery','stop')) {
            Assert ($failureException.Data.Contains('RollbackComplete') -and !$failureException.Data['RollbackComplete']) "$case incomplete recovery explicitly reported"
            Assert (Test-Path -LiteralPath (Join-Path $work 'metadata-0.bak')) "$case recovery metadata retained"
            if ($case -eq 'stop') {
                Assert ($backups.Count -eq 1) 'cannot stop new process: keep old backup'
                Assert ([IO.File]::ReadAllText((Join-Path $backups[0].FullName 'Layout_Toolkit_RU_EN.ahk')) -eq 'OLD_VERSION') 'retained backup contains old version'
                Assert ([IO.File]::ReadAllText((Join-Path $target 'Layout_Toolkit_RU_EN.ahk')) -like 'NEW_VERSION*') 'cannot stop new process: do not move its active directory'
            } else {
                Assert ([IO.File]::ReadAllText((Join-Path $sourceTarget 'Layout_Toolkit_RU_EN.ahk')) -eq 'OLD_VERSION') 'metadata recovery failure leaves restored old files'
                Assert (@(Get-ChildItem -LiteralPath $caseRoot -Directory -Force | Where-Object Name -like '.layout-toolkit-staging-*').Count -eq 1) 'incomplete rollback keeps diagnostic payload'
            }
            continue
        }
        Assert ($backups.Count -eq 0) "$case backup cleaned or restored"
        Assert (@(Get-ChildItem -LiteralPath $caseRoot -Directory -Force | Where-Object Name -like '.layout-toolkit-staging-*').Count -eq 0) "$case staging cleaned"
        if ($success) {
            Assert ([IO.File]::ReadAllText((Join-Path $target 'Layout_Toolkit_RU_EN.ahk')) -like 'NEW_VERSION*') "$case new files retained"
            Assert ((Get-Content -Raw $statePath | ConvertFrom-Json).installPath -eq $target) "$case canonical path committed"
            Assert ((Get-Content -Raw $statePath | ConvertFrom-Json).installedVersion -eq '1.5.0') "$case version committed"
            if ($case -eq 'foreignlegacy-success') { Assert ((Bytes $legacyStartupPath) -ceq $saved[$legacyStartupPath]) 'foreign legacy link retained' }
            else { Assert (!(Test-Path -LiteralPath $legacyStartupPath)) "$case legacy startup replaced" }
            $expectedEvents = if ($case -eq 'legacy-success') { 'health,start,state,shortcut' } elseif ($case -eq 'noautostart-success') { 'start,state' } else { 'start,state,shortcut' }
            Assert (($events -join ',') -eq $expectedEvents) "$case startup precedes metadata commit"
            if ($case -eq 'noautostart-success') {
                Assert (!(Test-Path -LiteralPath $startupPath)) 'disabled autostart removes only owned link'
                Assert (!(Get-Content -Raw $statePath | ConvertFrom-Json).autostart) 'disabled autostart recorded'
            }
        } else {
            if ($hasOld) {
                Assert ([IO.File]::ReadAllText((Join-Path $sourceTarget 'Layout_Toolkit_RU_EN.ahk')) -eq 'OLD_VERSION') "$case previous files restored"
                foreach ($path in $saved.Keys) { Assert ((Bytes $path) -ceq $saved[$path]) "$case metadata restored byte-for-byte" }
                if ($case -eq 'legacy-state') { Assert (!(Test-Path -LiteralPath $statePath)) 'failed legacy migration leaves no new install.json' }
                if ($sourceTarget -ne $target) { Assert (!(Test-Path -LiteralPath $target)) "$case old misspelled path restored" }
            } else {
                Assert (!(Test-Path -LiteralPath $target)) "$case failed fresh install removed"
                Assert (!(Test-Path -LiteralPath $statePath)) "$case no new install state left"
            }
            if ($case -in @('state','shortcut')) { Assert ($events -contains 'stop') "$case new child stopped before rollback" }
            if ($case -in @('hash','size')) { Assert ($events.Count -eq 0) 'archive verified before health or installation' }
        }
    }
    Write-Output 'PASS: transactional update/fresh install, readiness failure, state/shortcut rollback, exact metadata, legacy/typo migration, foreign shortcuts, health/hash/size rejection and incomplete recovery'
} finally {
    if (![IO.Path]::GetFullPath($testRoot).StartsWith(([IO.Path]::GetFullPath($TargetRoot).TrimEnd('\') + '\lt-transaction-tests-'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe test cleanup path' }
    if (![IO.Path]::GetFullPath($workRoot).StartsWith(([IO.Path]::GetTempPath().TrimEnd('\') + '\lt-transaction-work-'), [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup path' }
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    if (Test-Path -LiteralPath $workRoot) { Remove-Item -LiteralPath $workRoot -Recurse -Force }
}
