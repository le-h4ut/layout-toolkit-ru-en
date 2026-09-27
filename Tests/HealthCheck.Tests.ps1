param([string]$AutoHotkeyPath = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe')
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'install.ps1'), [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | ForEach-Object Message | Out-String) }
$definitions = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)
Invoke-Expression (($definitions | ForEach-Object { $_.Extent.Text }) -join "`n")
function Assert($Condition, $Message) { if (!$Condition) { throw "FAIL: $Message" } }
function Start-Process {
    param($FilePath, $ArgumentList, $WorkingDirectory, $WindowStyle,
          $RedirectStandardOutput, $RedirectStandardError, [switch]$PassThru)
    $script:lastChild = Microsoft.PowerShell.Management\Start-Process @PSBoundParameters
    return $script:lastChild
}
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('lt-health-tests-' + [guid]::NewGuid().ToString('N'))
$process = $null
$passed = $false
try {
    $payload = Join-Path $testRoot 'payload'
    $logs = Join-Path $testRoot 'logs'
    New-Item -ItemType Directory -Path $payload, $logs | Out-Null
    foreach ($name in @('Modules','Assets','Layout_Toolkit_RU_EN.ahk','Run_Layout_Toolkit.cmd','Resolve_AutoHotkey.ps1','install.ps1','Manage_Startup.ps1','CHANGELOG.md')) {
        Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $payload -Recurse
    }
    $main = Join-Path $payload 'Layout_Toolkit_RU_EN.ahk'
    $source = [IO.File]::ReadAllText($main).Replace('A_MyDocuments "\Layout Toolkit"', 'A_ScriptDir "\UserData"')
    [IO.File]::WriteAllText($main, $source, [Text.UTF8Encoding]::new($true))
    Assert-ReleaseHealthProtocol $payload
    Invoke-ReleaseHealthCheck $AutoHotkeyPath $payload $logs
    Assert (!(Test-Path -LiteralPath (Join-Path $payload 'UserData'))) 'health check does not initialize a user profile'

    $asset = Join-Path $payload 'Assets\WebSettings\settings.js'
    Move-Item -LiteralPath $asset -Destination ($asset + '.saved')
    $failed = $false
    try { Invoke-ReleaseHealthCheck $AutoHotkeyPath $payload $logs } catch { $failed = $true }
    Assert $failed 'missing release asset fails health check'
    Move-Item -LiteralPath ($asset + '.saved') -Destination $asset

    [IO.File]::WriteAllText($main, $source + "`nthis is invalid syntax !!!", [Text.UTF8Encoding]::new($true))
    $failed = $false
    try { Invoke-ReleaseHealthCheck $AutoHotkeyPath $payload $logs } catch { $failed = $true }
    Assert $failed 'AHK syntax errors fail without a dialog'
    $warnings = $source + "`nLTWarningFixture() {`n    return`n    FileAppend(`"unreachable`", `"*`")`n}`n"
    [IO.File]::WriteAllText($main, $warnings, [Text.UTF8Encoding]::new($true))
    $failed = $false
    try { Invoke-ReleaseHealthCheck $AutoHotkeyPath $payload $logs } catch { $failed = $true; $warningError = $_.Exception.Message }
    Assert ($failed -and $warningError -like '*health-check*') 'load-time warning is captured as unhealthy, not a modal dialog or timeout'
    Assert ($script:lastChild.HasExited) 'warning probe completed without hanging'
    [IO.File]::WriteAllText($main, $source, [Text.UTF8Encoding]::new($true))

    # Real startup uses an isolated profile and no global shortcut assignments.
    $profile = Join-Path $payload 'UserData'
    New-Item -ItemType Directory -Path $profile | Out-Null
    [IO.File]::WriteAllText((Join-Path $profile 'settings.ini'), "[General]`r`nFirstRunDone=1`r`nLiveEnabled=0`r`n[Notifications]`r`nShowTrayTips=0`r`nPlaySound=0`r`n")
    [IO.File]::WriteAllText((Join-Path $payload 'Assets\hotkeys.default.ini'), "[Hotkeys]`r`n")
    $process = Start-ValidatedLayoutToolkit $AutoHotkeyPath $payload $logs
    Assert (!$process.HasExited) 'real initialization confirms readiness and stays running'
    Stop-OwnedProcess $process
    $process = $null

    [IO.File]::WriteAllText((Join-Path $profile 'hotkeys.ini'), "[Hotkeys]`r`nLayoutFull=invalid-key-name`r`n")
    $failed = $false
    try { $process = Start-ValidatedLayoutToolkit $AutoHotkeyPath $payload $logs } catch { $failed = $true; $startupError = $_.Exception.Message }
    Assert $failed 'hotkey initialization failure rejects startup'
    Assert ($startupError -like '*горячие клавиши*') "startup failure diagnosis: $startupError"
    Remove-Item -LiteralPath (Join-Path $profile 'hotkeys.ini')

    $brokenStartup = $source.Replace('LTHealth_PrepareStartupCheck()', "LTHealth_PrepareStartupCheck()`nif A_Args.Length`n    throw Error(`"startup fixture failure`")")
    [IO.File]::WriteAllText($main, $brokenStartup, [Text.UTF8Encoding]::new($true))
    $failed = $false
    try { $process = Start-ValidatedLayoutToolkit $AutoHotkeyPath $payload $logs } catch { $failed = $true; $startupError = $_.Exception.Message }
    Assert ($failed -and $startupError -like '*startup fixture failure*') "runtime startup exception returns a failure report without a dialog: $startupError"
    Assert ($script:lastChild.HasExited) 'startup exception leaves no running child'

    $earlyExit = $source.Replace('LTHealth_PrepareStartupCheck()', "LTHealth_PrepareStartupCheck()`nif A_Args.Length {`n    LTHealth_WriteReady(true)`n    ExitApp()`n}")
    [IO.File]::WriteAllText($main, $earlyExit, [Text.UTF8Encoding]::new($true))
    $failed = $false
    try { $process = Start-ValidatedLayoutToolkit $AutoHotkeyPath $payload $logs } catch { $failed = $true; $startupError = $_.Exception.Message }
    Assert ($failed -and $startupError -like '*завершилась*') 'readiness followed by immediate exit is not success'

    # Old releases must be refused before invoking an unsupported CLI mode.
    [IO.File]::WriteAllText($main, '#Requires AutoHotkey v2.0')
    $failed = $false
    try { Assert-ReleaseHealthProtocol $payload } catch { $failed = $true }
    Assert $failed 'old releases without the health protocol are not launched as probes'

    $hung = "#Requires AutoHotkey v2.0`n#SingleInstance Off`nPersistent`n"
    [IO.File]::WriteAllText($main, $hung, [Text.UTF8Encoding]::new($true))
    $failed = $false
    try { Invoke-ReleaseHealthCheck $AutoHotkeyPath $payload $logs 1500 } catch { $failed = $true; $timeoutMessage = $_.Exception.Message }
    Assert $failed 'hung health process is timed out'
    Assert ($timeoutMessage -like '*вовремя*') "health timeout diagnosis: $timeoutMessage"
    Assert ($script:lastChild.HasExited) 'the owned hung probe is stopped'
    $failed = $false
    try { $process = Start-ValidatedLayoutToolkit $AutoHotkeyPath $payload $logs 1500 } catch { $failed = $true; $startupError = $_.Exception.Message }
    Assert $failed 'startup without readiness is timed out'
    Assert ($startupError -like '*вовремя*') "startup timeout diagnosis: $startupError"
    Assert ($script:lastChild.HasExited) 'unready child process is stopped before rollback'

    $badReport = @'
#Requires AutoHotkey v2.0
#SingleInstance Off
FileAppend('{"protocol":1,"token":"wrong","pid":1,"scriptPath":"wrong","ready":true}', A_Args[2])
Persistent
'@
    [IO.File]::WriteAllText($main, $badReport, [Text.UTF8Encoding]::new($true))
    $failed = $false
    try { $process = Start-ValidatedLayoutToolkit $AutoHotkeyPath $payload $logs } catch { $failed = $true; $startupError = $_.Exception.Message }
    Assert $failed 'stale or forged readiness report is rejected'
    Assert ($startupError -like '*неверный ответ*') "readiness authentication diagnosis: $startupError"
    Assert ($script:lastChild.HasExited) 'invalid readiness child is stopped'
    Write-Output 'PASS: real health/startup checks, profile isolation, missing assets, syntax/hotkey failures, protocol, timeout and readiness authentication'
    $passed = $true
} finally {
    Stop-OwnedProcess $process
    if ($passed -and (Test-Path -LiteralPath $testRoot)) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
    elseif (Test-Path -LiteralPath $testRoot) { Write-Output "Failed fixture retained at: $testRoot" }
}
