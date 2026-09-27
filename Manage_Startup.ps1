[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Status', 'Install', 'Remove')]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$ScriptPath,

    [string]$StartupDirectory = ''
)

$ErrorActionPreference = 'Stop'
$scriptPath = [IO.Path]::GetFullPath($ScriptPath)
$programDir = Split-Path -Parent $scriptPath
$startupDir = if ($StartupDirectory) { [IO.Path]::GetFullPath($StartupDirectory) } else { [Environment]::GetFolderPath('Startup') }
$canonical = Join-Path $startupDir 'Layout Toolkit.lnk'
$legacy = Join-Path $startupDir 'Layout Toolkit RU-EN.lnk'
$launcher = Join-Path $programDir 'Run_Layout_Toolkit.cmd'

function Test-OwnShortcut([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    try {
        $link = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
        if ([string]::Equals($link.TargetPath, $launcher, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if ([string]::Equals($link.TargetPath, $scriptPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
        if (![string]::Equals($link.WorkingDirectory, $programDir, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        return ($link.TargetPath -match '(?i)\\(?:powershell|autohotkey(?:64|32)?)(?:\.exe)?$') -and
               $link.Arguments.Contains($scriptPath)
    } catch { return $false }
}

try {
    $present = @($canonical, $legacy) | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }
    $foreign = @($present | Where-Object { !(Test-OwnShortcut $_) })
    $own = @($present | Where-Object { Test-OwnShortcut $_ })

    switch ($Action) {
        'Status' {
            if ($foreign.Count) { Write-Output 'Current status: ANOTHER COPY HAS A STARTUP SHORTCUT'; exit 0 }
            if ($own.Count) { Write-Output 'Current status: INSTALLED IN STARTUP'; exit 0 }
            Write-Output 'Current status: NOT INSTALLED IN STARTUP'
        }
        'Install' {
            if ($foreign.Count) { throw 'A startup shortcut belongs to another copy. Check the Startup folder manually.' }
            if (!(Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw 'Layout_Toolkit_RU_EN.ahk was not found.' }
            $resolver = Join-Path $programDir 'Resolve_AutoHotkey.ps1'
            if (!(Test-Path -LiteralPath $resolver -PathType Leaf)) { throw 'Resolve_AutoHotkey.ps1 was not found.' }
            $icon = Join-Path $programDir 'Assets\icon.ico'
            & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $resolver -Action InstallStartup -ScriptPath $scriptPath -IconPath $icon -StartupLink $canonical
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
            if (!(Test-OwnShortcut $canonical)) { throw 'The startup shortcut could not be verified.' }
            if (Test-OwnShortcut $legacy) { Remove-Item -LiteralPath $legacy -Force }
            Write-Host 'Startup shortcut installed.'
        }
        'Remove' {
            foreach ($path in $own) { Remove-Item -LiteralPath $path -Force }
            if ($foreign.Count) { Write-Host 'Only this copy was removed; another copy remains in Startup.' }
            else { Write-Host 'Startup shortcut removed.' }
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
