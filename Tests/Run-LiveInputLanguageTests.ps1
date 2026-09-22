param(
    [string]$AutoHotkeyPath = 'C:\Program Files\AutoHotkey\v2\AutoHotkey64.exe',
    [switch]$RealInput,
    [string]$RepoRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$SourcePath = (Join-Path $RepoRoot 'Layout_Toolkit_RU_EN.ahk')
)

$ErrorActionPreference = 'Stop'
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('lt-live-language-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null

Copy-Item -LiteralPath (Join-Path $repoRoot 'Modules'), (Join-Path $repoRoot 'Assets') -Destination $testDir -Recurse
Copy-Item -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md') -Destination $testDir

$source = Get-Content -Raw -LiteralPath $SourcePath
$source = $source.Replace('A_MyDocuments "\Layout Toolkit"', 'A_ScriptDir "\UserData"')
$source = $source -replace '(?m)^MigrateUserData\(\)\r?$', '; Migration disabled in the test fixture.'
$entryFunction = $RealInput ? 'RunLiveInputLanguageIntegrationTests()' : 'RunLiveInputLanguageTests()'
$source = $source -replace '(?m)^SetupTrayMenu\(\)\r?$', $entryFunction
$source = $source -replace '(?m)^~[LRM]Button::.*\r?$', ''
$source = $source -replace '(?m)^\$\*Space::.*\r?$', ''
$source = $source.Replace('ih.Start()', 'LiveTest_NoOp()')
$source = $source -creplace '\bHotkey\(', 'LiveTest_NoOp('
$source = $source -replace '(?m)^global g_ShowTrayTips := .*$', 'global g_ShowTrayTips := false'
$source = $source -replace '(?m)^global g_PlaySound := .*$', 'global g_PlaySound := false'
$source = $source.Replace('ShowTrainingGui(true)', 'LiveTest_NoOp()')
$source = $source -replace '(?m)^RegisterHotkeys\(\)\r?$', '; Hotkey registration disabled in the test fixture.'
$source = $source -replace '(?m)^SetTimer\(ObjBindMethod\(LTWebUnicodeInput, "Prewarm"\), -1500\)\r?$', ''
$source = $source -replace '(?m)^OnExit\(\(\*\) => LTWebUnicodeInput\.Dispose\(\)\)\r?$', ''

if ($RealInput) {
    $source += "`n" + (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'LiveInputLanguage.Integration.ahk'))
} else {
    # Isolate every side effect used by DoLiveConvertAndReplace while retaining
    # its real transaction, direction detection, target-window guards and cleanup.
    $source = $source.Replace('A_Clipboard', 'g_LiveTestClipboard')
    $source = $source.Replace('ClipboardAll()', 'LiveTest_ClipboardAll()')
    $source = $source.Replace('ClipWait(', 'LiveTest_ClipWait(')
    $source = $source.Replace('SendInput sendSequence', 'LiveTest_Send(sendSequence)')
    $source = $source.Replace('SendInput pendingSequence "{Text}" pendingOutput', 'LiveTest_SendPending(pendingOutput)')
    $source = $source.Replace('SetLiveInputBuffering(true)', 'LiveTest_SetInputBuffering(true)')
    $source = $source.Replace('SetLiveInputBuffering(false)', 'LiveTest_SetInputBuffering(false)')
    $source = $source.Replace('Sleep 450', 'LiveTest_NoOp(450)')
    $source = $source.Replace('Sleep 60', 'LiveTest_NoOp(60)')
    $source = $source.Replace('WinExist("A")', 'LiveTest_WinExist()')
    $source = $source -replace '(?m)^global g_LastWindow := LiveTest_WinExist\(\)\r?$', 'global g_LastWindow := 100'
    $source = $source.Replace('hkl := FindInstalledKeyboardLayout(direction)', 'hkl := LiveTest_FindInstalledKeyboardLayout(direction)')
    $source = $source.Replace('inputWindow := GetLiveInputTargetHwnd(targetWindow)', 'inputWindow := LiveTest_GetLiveInputTargetHwnd(targetWindow)')
    $source = $source.Replace('GetLiveInputTargetHwnd(targetWindow) != inputWindow', 'LiveTest_GetLiveInputTargetHwnd(targetWindow) != inputWindow')
    $source = $source.Replace('GetLiveInputTargetHwnd(targetWindow) = inputWindow', 'LiveTest_GetLiveInputTargetHwnd(targetWindow) = inputWindow')
    $source = $source.Replace('GetWindowKeyboardLayout(inputWindow)', 'LiveTest_GetWindowKeyboardLayout(inputWindow)')
    $source = $source.Replace('requestPosted := PostLiveInputLanguageRequest(inputWindow, hkl)', 'requestPosted := LiveTest_PostInputLanguageRequest(inputWindow, hkl)')
    $source = $source.Replace('return PostLiveInputLanguageRequest(inputWindow, hkl)', 'return LiveTest_PostInputLanguageRequest(inputWindow, hkl)')
    $source = $source.Replace('return PostLiveInputLanguageRequest(targetWindow, hkl)', 'return LiveTest_PostInputLanguageRequest(targetWindow, hkl)')
    $source = $source.Replace('if !PostLiveInputLanguageRequest(targetWindow, hkl)', 'if !LiveTest_PostInputLanguageRequest(targetWindow, hkl)')
    $source += "`n" + (Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'LiveInputLanguage.Tests.ahk'))
}

$entryPath = Join-Path $testDir 'LiveInputLanguage.TestRuntime.ahk'
[IO.File]::WriteAllText($entryPath, $source, [Text.UTF8Encoding]::new($true))

$stderr = Join-Path $testDir 'stderr.txt'
$stdout = Join-Path $testDir 'stdout.txt'
$process = Start-Process -FilePath $AutoHotkeyPath -ArgumentList @('/ErrorStdOut=UTF-8', ('"' + $entryPath + '"')) -WindowStyle Hidden -RedirectStandardError $stderr -RedirectStandardOutput $stdout -PassThru
if (!$process.WaitForExit(10000)) {
    Stop-Process -Id $process.Id
    throw "Tests timed out. Logs: $testDir"
}
$process.WaitForExit()
$process.Refresh()
$outputText = [string](Get-Content -Raw -LiteralPath $stdout)
$errorText = [string](Get-Content -Raw -LiteralPath $stderr)
if ($outputText) { Write-Output $outputText.TrimEnd() }
if ($errorText -or $outputText -notmatch '(?m)^PASS:') { throw $errorText }
Write-Output "Isolated test files retained at: $testDir"
