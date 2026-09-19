param(
    [Parameter(Mandatory = $true)]
    [string]$AutoHotkeyPath
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path $PSScriptRoot -Parent
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('lt-caps-selection-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null
try {
    # Execute the production selection handler with clipboard and input replaced
    # by in-memory test doubles. No real keyboard input or clipboard access.
    $module = Get-Content -Raw -LiteralPath (Join-Path $repoRoot 'Modules\CapsLockFix.ahk')
    $module = $module.Replace('A_Clipboard', 'g_TestClipboard')
    $module = $module.Replace('global g_AppName', 'global g_AppName, g_TestClipboard')
    $module = $module -creplace '\b(ClipboardAll|Send|Sleep|ClipWait)\b', 'Test_$1'
    $tests = Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'CapsLockFix.Tests.ahk')
    $tests = $tests.Replace('#Include ..\Modules\CapsLockFix.ahk', $module)
    $tests = $tests.Replace('    RunCapsLockFixTests()', "    RunCapsLockFixTests()`n    RunSelectionTests()")
    $tests += @'

Test_ClipboardAll() {
    global g_TestClipboard
    return g_TestClipboard
}
Test_Send(keys) {
    global g_TestClipboard, g_TestInput, g_TestPastes
    if (keys == "^c") {
        g_TestClipboard := g_TestInput
    } else if (keys == "^v") {
        g_TestPastes.Push(g_TestClipboard)
    } else {
        throw Error("Unexpected input: " keys)
    }
}
Test_Sleep(*) {
}
Test_ClipWait(*) {
    return true
}
RunSelectionTests() {
    global g_TestClipboard, g_TestInput, g_TestPastes
    cases := [
        ["Full", "cORE jAM", "Core Jam"],
        ["Smart", "cORE jAM", "Core jam"],
        ["Full", "pOWERSHELL", "PowerShell"],
        ["Smart", "pOWERSHELL", "PowerShell"],
        ["Full", "123 !?", ""],
        ["Full", "PowerShell", ""],
        ["Smart", "Привет", ""]
    ]
    for item in cases {
        g_TestClipboard := "original clipboard"
        g_TestInput := item[2]
        g_TestPastes := []
        CapsFix_ReplaceSelectedText(item[1])
        expectedCount := item[3] == "" ? 0 : 1
        AssertEqual(expectedCount, g_TestPastes.Length, "paste count: " item[1] " " item[2])
        if expectedCount {
            AssertEqual(item[3], g_TestPastes[1], "pasted text")
        }
        AssertEqual("original clipboard", g_TestClipboard, "clipboard restoration")
    }
}
'@
    $testPath = Join-Path $testDir 'Selection.Tests.ahk'
    [IO.File]::WriteAllText($testPath, $tests, [Text.UTF8Encoding]::new($true))
    $stderr = Join-Path $testDir 'stderr.txt'
    $process = Start-Process -FilePath $AutoHotkeyPath -ArgumentList @('/ErrorStdOut=UTF-8', ('"' + $testPath + '"')) -WindowStyle Hidden -RedirectStandardError $stderr -PassThru
    if (!$process.WaitForExit(15000)) {
        Stop-Process -Id $process.Id
        throw 'CapsLock selection tests timed out'
    }
    if ($process.ExitCode -ne 0) {
        throw ('CapsLock selection tests failed: ' + (Get-Content -Raw -LiteralPath $stderr))
    }
    Write-Output 'PASS: conversion, case-sensitive assertions, selection paste and clipboard restoration'
} finally {
    $resolved = [IO.Path]::GetFullPath($testDir)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (!$resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Unsafe test cleanup path'
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
