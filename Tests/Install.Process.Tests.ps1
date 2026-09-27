param([string]$Repo = (Split-Path $PSScriptRoot -Parent), [string]$AutoHotkeyPath = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe')
$ErrorActionPreference = 'Stop'
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('lt-installer-process-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$children = @()
$savedModulePath = $env:PSModulePath
# Start-Process from PS7 otherwise passes its incompatible module search path
# to Windows PowerShell 5.1; normal desktop/AHK launches do not do that.
$env:PSModulePath = "$env:WINDIR\System32\WindowsPowerShell\v1.0\Modules;$env:ProgramFiles\WindowsPowerShell\Modules"
function Assert($Value, $Message) { if (!$Value) { throw "FAIL: $Message" } }
try {
    foreach ($case in @('success','health')) {
        $caseRoot = Join-Path $testRoot $case
        $target = Join-Path $caseRoot 'Layout Toolkit'
        $payload = Join-Path $caseRoot 'payload'
        $stateRoot = Join-Path $caseRoot 'LocalAppData'
        New-Item -ItemType Directory -Path $target, $payload, (Join-Path $caseRoot 'Startup'), (Join-Path $payload 'Modules\Vendor'), (Join-Path $stateRoot 'Layout Toolkit') | Out-Null
        [IO.File]::WriteAllText((Join-Path $target 'Layout_Toolkit_RU_EN.ahk'),'OLD_VERSION')
        [IO.File]::WriteAllText((Join-Path $target 'Run_Layout_Toolkit.cmd'),'@echo off')
        Copy-Item -LiteralPath (Join-Path $Repo 'Modules\Vendor\JSON.ahk') -Destination (Join-Path $payload 'Modules\Vendor')
        Copy-Item -LiteralPath (Join-Path $Repo 'Modules\HealthCheck.ahk') -Destination (Join-Path $payload 'Modules')
        Copy-Item -LiteralPath (Join-Path $Repo 'Resolve_AutoHotkey.ps1') -Destination $payload
        $fixture = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
#Include Modules/Vendor/JSON.ahk
LTHealth_Run() {
    if FileExist(A_ScriptDir "\fail-health") {
        FileAppend("fixture health failure`n", "**", "UTF-8")
        ExitApp(1)
    }
    FileAppend("LAYOUT_TOOLKIT_HEALTH_OK`n", "*", "UTF-8")
    ExitApp(0)
}
if A_Args[1] = "--health-check"
    LTHealth_Run()
FileAppend(ProcessExist(), A_ScriptDir "\test-child.pid", "UTF-8")
FileAppend(JSON.stringify(Map("protocol", 1, "token", A_Args[4], "pid", ProcessExist(),
    "scriptPath", A_ScriptFullPath, "ready", JSON.true, "error", "")), A_Args[2], "UTF-8")
Persistent()
'@
        [IO.File]::WriteAllText((Join-Path $payload 'Layout_Toolkit_RU_EN.ahk'),$fixture,[Text.UTF8Encoding]::new($true))
        [IO.File]::WriteAllText((Join-Path $payload 'Run_Layout_Toolkit.cmd'),'@echo off')
        if ($case -eq 'health') { [IO.File]::WriteAllText((Join-Path $payload 'fail-health'),'fail') }
        $archive = Join-Path $caseRoot 'release.zip'
        Compress-Archive -LiteralPath $payload -DestinationPath $archive
        $manifest = [ordered]@{schema_version=1;version='1.5.1';channel='stable';assets=@{windows=@{url='https://fixture.invalid/release.zip';size=(Get-Item $archive).Length;sha256=(Get-FileHash $archive).Hash}}}
        [IO.File]::WriteAllText((Join-Path $caseRoot 'manifest.json'),($manifest | ConvertTo-Json -Depth 5))
        [IO.File]::WriteAllText((Join-Path $stateRoot 'Layout Toolkit\autohotkey-path.txt'),$AutoHotkeyPath)
        $source = [IO.File]::ReadAllText((Join-Path $Repo 'install.ps1'))
        $source = $source.Replace("`$stateDir = Join-Path `$env:LOCALAPPDATA 'Layout Toolkit'", "`$stateDir = Join-Path `$env:LT_TEST_ROOT 'LocalAppData\Layout Toolkit'")
        $source = $source.Replace("`$startupPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Layout Toolkit.lnk'", "`$startupPath = Join-Path `$env:LT_TEST_ROOT 'Startup\Layout Toolkit.lnk'")
        $source = $source.Replace("`$legacyStartupPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Layout Toolkit RU-EN.lnk'", "`$legacyStartupPath = Join-Path `$env:LT_TEST_ROOT 'Startup\Layout Toolkit RU-EN.lnk'")
        $overrides = @'
function Invoke-RestMethod($Uri) { return Get-Content -Raw -LiteralPath (Join-Path $env:LT_TEST_ROOT 'manifest.json') | ConvertFrom-Json }
function Invoke-WebRequest($Uri, $OutFile, [switch]$UseBasicParsing) { Copy-Item -LiteralPath (Join-Path $env:LT_TEST_ROOT 'release.zip') -Destination $OutFile }
Invoke-InstallerWithDiagnostics
'@
        $source = [regex]::Replace($source,'(?m)^Invoke-InstallerWithDiagnostics\r?$',{param($match) $overrides})
        $installer = Join-Path $target 'install.ps1'
        [IO.File]::WriteAllText($installer,$source,[Text.UTF8Encoding]::new($true))
        $env:LT_TEST_ROOT = $caseRoot
        $process = Start-Process -FilePath "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "{0}" -Update -InstallPath "{1}" -NoAutostart' -f $installer,$target) -WorkingDirectory $target -WindowStyle Hidden -RedirectStandardOutput (Join-Path $caseRoot 'stdout.txt') -RedirectStandardError (Join-Path $caseRoot 'stderr.txt') -PassThru
        $children += $process
        Assert ($process.WaitForExit(30000)) "$case installer process finishes"
        $process.Refresh()
        $pidFile = Join-Path $target 'test-child.pid'
        if (Test-Path -LiteralPath $pidFile) {
            $child = Get-Process -Id ([int][IO.File]::ReadAllText($pidFile)) -ErrorAction SilentlyContinue
            if ($child) { $children += $child }
        }
        $logs = @(Get-ChildItem -LiteralPath (Join-Path $stateRoot 'Layout Toolkit\Logs') -Directory)
        Assert ($logs.Count -eq 1) "$case retains persistent diagnostics"
        if ($case -eq 'success') {
            Assert ($process.ExitCode -eq 0) ('success exit code: ' + (Get-Content -Raw (Join-Path $caseRoot 'stderr.txt')))
            Assert ((Get-Content -Raw (Join-Path $stateRoot 'Layout Toolkit\install.json') | ConvertFrom-Json).installedVersion -eq '1.5.1') 'installed version committed'
            Assert (Test-Path -LiteralPath $pidFile) 'real new AHK child confirmed startup'
        } else {
            Assert ($process.ExitCode -ne 0) 'health failure reported'
            Assert ([IO.File]::ReadAllText((Join-Path $target 'Layout_Toolkit_RU_EN.ahk')) -eq 'OLD_VERSION') 'failure preserves original installation'
            Assert (Test-Path -LiteralPath (Join-Path $logs[0].FullName 'error.txt')) 'full error retained'
            Assert (Test-Path -LiteralPath (Join-Path $logs[0].FullName 'health.stderr.txt')) 'probe output retained'
            Assert (!(Test-Path -LiteralPath (Join-Path $stateRoot 'Layout Toolkit\install.json'))) 'no new install state on failure'
        }
        foreach ($child in $children) { if (!$child.HasExited) { $child.Kill(); $null = $child.WaitForExit(5000) } }
        $children = @()
    }
    Write-Output 'PASS: complete installer launched inside target, real resolver/health/startup and persistent failure logs'
} finally {
    foreach ($child in $children) { if (!$child.HasExited) { $child.Kill(); $null = $child.WaitForExit(5000) } }
    Remove-Item Env:LT_TEST_ROOT -ErrorAction SilentlyContinue
    $env:PSModulePath = $savedModulePath
    Write-Output "Process fixtures retained: $testRoot"
}
