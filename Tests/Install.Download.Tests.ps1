param([string]$InstallerUrl = 'https://raw.githubusercontent.com/le-h4ut/layout-toolkit-ru-en/main/install.ps1')
$ErrorActionPreference = 'Stop'
function Assert($Value, $Message) { if (!$Value) { throw "FAIL: $Message" } }
$raw = Invoke-RestMethod -Uri $InstallerUrl
$source = $raw.TrimStart([char]0xFEFF)
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0 -and $null -ne $ast.ParamBlock) 'downloaded script parses with a parameter block'
# Replace ONLY the installer entry point: no install, UI or metadata writes.
$entry = '(?m)^Invoke-InstallerWithDiagnostics\r?$'
Assert ([regex]::Matches($source,$entry).Count -eq 1) 'exactly one installer entry point'
$probe = [regex]::Replace($source,$entry,'[pscustomobject]@{Path=$InstallPath;Update=[bool]$Update;NoAutostart=[bool]$NoAutostart;Uninstall=[bool]$Uninstall;WaitForPid=$WaitForPid}')
$explicit = & ([scriptblock]::Create($probe)) -Update -InstallPath 'D:\Scripts\LT My' -NoAutostart
Assert ($explicit.Path -eq 'D:\Scripts\LT My' -and $explicit.Update -and $explicit.NoAutostart -and !$explicit.Uninstall) 'explicit update parameters bind'
$defaults = $probe | Invoke-Expression
Assert (!$defaults.Update -and !$defaults.NoAutostart -and !$defaults.Uninstall -and $defaults.WaitForPid -eq 0) 'pipeline evaluation uses declared defaults'
Write-Output 'PASS: actual GitHub download, BOM removal, ScriptBlock parameters and pipeline defaults; installer entry point isolated'
