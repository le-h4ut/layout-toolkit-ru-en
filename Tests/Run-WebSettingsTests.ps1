param(
    [string]$AutoHotkeyPath = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
    [switch]$Preview,
    [switch]$BrowserTests,
    [switch]$SettingsLifecycleTests,
    [switch]$UnicodePreview,
    [switch]$UnicodeBrowserTests,
    [switch]$WelcomeBrowserTests,
    [switch]$PrewarmTests
)
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('lt-web-settings-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
# Isolated runtime: no access to the real profile, no global hotkey registration,
# no input synthesis or clipboard usage. Production UI and save handlers are used.
Copy-Item -LiteralPath (Join-Path $repoRoot 'Modules'), (Join-Path $repoRoot 'Assets') -Destination $testDir -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md') -Destination $testDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'WebSettings.BrowserTests.js') -Destination $testDir
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'WebUnicode.BrowserTests.js') -Destination $testDir
$source = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'Layout_Toolkit_RU_EN.ahk')
$source = $source.Replace('A_MyDocuments "\Layout Toolkit"', 'A_ScriptDir "\UserData"')
$source = $source -replace '(?m)^MigrateUserData\(\)\r?$', '; Migration disabled in the test fixture.'
$source = $source -replace '(?m)^~[LRM]Button::.*\r?$', ''
$source = $source -replace '(?m)^\$\*Space::.*\r?$', ''
$source = $source.Replace('ih.Start()', 'WebTest_NoOp()')
$source = $source -creplace '\bHotkey\(', 'WebTest_NoOp('
$source = $source -replace '(?m)^global g_ShowTrayTips := .*$', 'global g_ShowTrayTips := false'
$source = $source -replace '(?m)^global g_PlaySound := .*$', 'global g_PlaySound := false'
$source = $source.Replace('ShowTrainingGui(true)', 'WebTest_NoOp()')
$entry = if ($Preview) { 'LTWebSettings.Open()' } elseif ($BrowserTests) { 'LTWebSettings.Open(), SetTimer(WebTest_BrowserRun, -100)' } elseif ($SettingsLifecycleTests) { 'WebTest_StartSettingsLifecycle()' } elseif ($UnicodePreview) { 'WebTest_StartUnicodePreview()' } elseif ($UnicodeBrowserTests) { 'WebTest_StartUnicodeBrowser()' } elseif ($WelcomeBrowserTests) { 'WebTest_StartWelcomeBrowser()' } elseif ($PrewarmTests) { 'WebTest_StartPrewarmTimer()' } else { 'WebTest_Run()' }
$source = $source -replace '(?m)^RegisterHotkeys\(\)\r?$', $entry
$source += "`nWebTest_NoOp(*) {`n}`n"
$source += "`n" + (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'WebSettings.Tests.ahk'))
$entryPath = Join-Path $testDir 'WebSettings.TestRuntime.ahk'
[IO.File]::WriteAllText($entryPath, $source, [Text.UTF8Encoding]::new($true))
$webPath = Join-Path $testDir 'Modules\WebSettings.ahk'
$web = Get-Content -Raw -LiteralPath $webPath
$web = $web.Replace('EnvGet("LOCALAPPDATA") "\Layout Toolkit\WebView2"', 'A_ScriptDir "\WebView2Profile"')
[IO.File]::WriteAllText($webPath, $web, [Text.UTF8Encoding]::new($true))
$unicodeWebPath = Join-Path $testDir 'Modules\WebUnicodeInput.ahk'
$unicodeWeb = Get-Content -Raw -LiteralPath $unicodeWebPath
$unicodeWeb = $unicodeWeb.Replace('EnvGet("LOCALAPPDATA") "\Layout Toolkit\WebView2\UnicodeInput"', 'A_ScriptDir "\WebView2UnicodeProfile"')
$unicodeWeb = $unicodeWeb.Replace('UnicodeInput_ApplyResult(text, mode)', 'WebTest_UnicodeApplyResult(text, mode)')
[IO.File]::WriteAllText($unicodeWebPath, $unicodeWeb, [Text.UTF8Encoding]::new($true))
$welcomeWebPath = Join-Path $testDir 'Modules\WebWelcome.ahk'
$welcomeWeb = Get-Content -Raw -LiteralPath $welcomeWebPath
$welcomeWeb = $welcomeWeb.Replace('EnvGet("LOCALAPPDATA") "\Layout Toolkit\WebView2\Welcome"', 'A_ScriptDir "\WebView2WelcomeProfile"')
[IO.File]::WriteAllText($welcomeWebPath, $welcomeWeb, [Text.UTF8Encoding]::new($true))
if ($UnicodeBrowserTests) {
    # Force the page handshake to arrive later than Open(), reproducing the
    # startup race that used to expose an empty WebView container.
    $unicodeJsPath = Join-Path $testDir 'Assets\WebUnicodeInput\unicode.js'
    $unicodeJs = Get-Content -Raw -LiteralPath $unicodeJsPath
    $unicodeJs = $unicodeJs.Replace(
        'if (bridge) request("state").then(result => { state = result; render(); }).catch(error => toast(error.message, true));',
        'if (bridge) setTimeout(() => request("state").then(result => { state = result; render(); }).catch(error => toast(error.message, true)), 500);'
    )
    [IO.File]::WriteAllText($unicodeJsPath, $unicodeJs, [Text.UTF8Encoding]::new($true))
}
$stderr = Join-Path $testDir 'stderr.txt'
$stdout = Join-Path $testDir 'stdout.txt'
$process = Start-Process -FilePath $AutoHotkeyPath -ArgumentList @('/ErrorStdOut=UTF-8', ('"' + $entryPath + '"')) -WindowStyle Hidden -RedirectStandardError $stderr -RedirectStandardOutput $stdout -PassThru
if ($Preview -or $UnicodePreview) {
    Write-Output "Preview PID: $($process.Id)"
    Write-Output "Isolated fixture: $testDir"
    exit 0
}
if (!$process.WaitForExit(45000)) {
    Stop-Process -Id $process.Id
    throw "Tests timed out. Logs: $testDir"
}
Get-Content -LiteralPath $stdout
if ($process.ExitCode -ne 0) { throw (Get-Content -Raw -LiteralPath $stderr) }
Write-Output "Isolated test files retained at: $testDir"
