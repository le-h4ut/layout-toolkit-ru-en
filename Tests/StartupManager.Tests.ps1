$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$manager = Join-Path $root 'Manage_Startup.ps1'
$script = Join-Path $root 'Layout_Toolkit_RU_EN.ahk'
$testDir = Join-Path ([IO.Path]::GetTempPath()) ('lt-startup-tests-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $testDir | Out-Null
    $own = Join-Path $testDir 'Layout Toolkit.lnk'
    $foreign = Join-Path $testDir 'Layout Toolkit RU-EN.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $link = $shell.CreateShortcut($own)
    $link.TargetPath = Join-Path $root 'Run_Layout_Toolkit.cmd'
    $link.WorkingDirectory = $root
    $link.Save()
    $link = $shell.CreateShortcut($foreign)
    $link.TargetPath = Join-Path $testDir 'other-copy.cmd'
    $link.Save()
    $status = & $manager -Action Status -ScriptPath $script -StartupDirectory $testDir
    if ($status -notmatch 'ANOTHER COPY') { throw 'Foreign startup shortcut was not reported.' }
    & $manager -Action Remove -ScriptPath $script -StartupDirectory $testDir | Out-Null
    if ((Test-Path -LiteralPath $own) -or !(Test-Path -LiteralPath $foreign)) {
        throw 'Removal did not preserve the foreign shortcut.'
    }
    $link = $shell.CreateShortcut($own)
    $link.TargetPath = $script
    $link.Save()
    & $manager -Action Remove -ScriptPath $script -StartupDirectory $testDir | Out-Null
    if (Test-Path -LiteralPath $own) { throw 'Legacy direct-script shortcut was not removed.' }
    Write-Output 'PASS: startup helper distinguishes own and foreign shortcuts and removes only own'
} finally {
    if (Test-Path -LiteralPath $testDir) { Remove-Item -LiteralPath $testDir -Recurse -Force }
}
