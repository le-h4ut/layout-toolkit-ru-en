$ErrorActionPreference = 'Stop'
$installerPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'install.ps1'
$source = Get-Content -Raw -LiteralPath $installerPath
$tokens = $null
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | ForEach-Object Message | Out-String) }
$hasReadHost = $source -match '\bRead-Host\b'
$hasFolderPicker = $source -match '\.BrowseForFolder\('
$definitions = $ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] }, $true)
Invoke-Expression (($definitions | ForEach-Object { $_.Extent.Text }) -join "`n`n")

function Assert($Condition, [string]$Message) {
    if (!$Condition) { throw "FAIL: $Message" }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('lt-installer-tests-' + [guid]::NewGuid().ToString('N'))
try {
    $legacyInstall = Join-Path $testRoot 'Old Layout Toolkit'
    New-Item -ItemType Directory -Path $legacyInstall -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $legacyInstall 'Layout_Toolkit_RU_EN.ahk') -Value '# test'
    Set-Content -LiteralPath (Join-Path $legacyInstall 'Run_Layout_Toolkit.cmd') -Value '@echo off'

    $legacyStartupPath = Join-Path $testRoot 'Layout Toolkit RU-EN.lnk'
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($legacyStartupPath)
    $shortcut.TargetPath = Join-Path $legacyInstall 'Run_Layout_Toolkit.cmd'
    $shortcut.Save()

    Assert ((Find-LegacyInstall) -eq $legacyInstall) 'legacy shortcut resolves a direct launcher target'

    $shortcut = $shell.CreateShortcut($legacyStartupPath)
    $shortcut.TargetPath = Join-Path $PSHOME 'powershell.exe'
    $shortcut.Arguments = '-NoProfile -File "C:\Old\Resolve_AutoHotkey.ps1" -Action Run -ScriptPath "' + (Join-Path $legacyInstall 'Layout_Toolkit_RU_EN.ahk') + '"'
    $shortcut.Save()

    Assert ((Find-LegacyInstall) -eq $legacyInstall) 'legacy shortcut resolves the script path from arguments'
    Assert ((Resolve-InstallPath '' $legacyInstall $true) -eq $legacyInstall) 'detected update path bypasses folder picker'
    Assert ((Resolve-InstallPath $legacyInstall '' $false) -eq $legacyInstall) 'explicit path bypasses folder picker'
    $misspelledInstall = Join-Path $testRoot 'Layout Toolkir Ru En'
    $canonicalInstall = Join-Path $testRoot 'Layout Toolkit Ru En'
    Assert ((Get-CanonicalUpdatePath $misspelledInstall) -eq $canonicalInstall) '1.4.1 and beta.1 folder typo is corrected during update'
    Assert ((Get-CanonicalUpdatePath $legacyInstall) -eq $legacyInstall) 'already canonical install path stays unchanged'
    $customInstall = Join-Path $testRoot 'My Toolkir Project'
    Assert ((Get-CanonicalUpdatePath $customInstall) -eq $customInstall) 'unrelated user folder is never renamed'
    New-Item -ItemType Directory -Path $misspelledInstall -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $misspelledInstall 'Layout_Toolkit_RU_EN.ahk') -Value '# test'
    Set-Content -LiteralPath (Join-Path $misspelledInstall 'Run_Layout_Toolkit.cmd') -Value '@echo off'
    Assert ((Resolve-UpdateSourcePath $misspelledInstall $canonicalInstall) -eq $misspelledInstall) 'existing misspelled folder remains the update source'
    New-Item -ItemType Directory -Path $canonicalInstall -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $canonicalInstall 'Layout_Toolkit_RU_EN.ahk') -Value '# test'
    Set-Content -LiteralPath (Join-Path $canonicalInstall 'Run_Layout_Toolkit.cmd') -Value '@echo off'
    $collisionRejected = $false
    try { Assert-CanonicalUpdateDestination $misspelledInstall $canonicalInstall } catch { $collisionRejected = $true }
    Assert $collisionRejected 'canonical folder collision is rejected before update'
    Remove-Item -LiteralPath $misspelledInstall -Recurse -Force
    Assert ((Resolve-UpdateSourcePath $misspelledInstall $canonicalInstall) -eq $canonicalInstall) 'stale install.json recovers an already migrated canonical folder'
    Assert (!$hasReadHost) 'interactive installation does not request a path with Read-Host'
    Assert $hasFolderPicker 'interactive installation uses the Windows folder picker'

    Remove-Item -LiteralPath (Join-Path $legacyInstall 'Run_Layout_Toolkit.cmd')
    Assert ($null -eq (Find-LegacyInstall)) 'legacy shortcut is rejected when required files are missing'

    $message = ''
    try { Resolve-InstallPath '' '' $true | Out-Null } catch { $message = $_.Exception.Message }
    Assert ($message -like '*-InstallPath*') 'missing legacy update explains explicit path fallback'
    Write-Output 'PASS: installer syntax, legacy migration detection, validation and non-interactive path resolution'
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
