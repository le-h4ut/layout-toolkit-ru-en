[CmdletBinding()]
param(
    [ValidateSet('Native', 'Web', 'Status')]
    [string]$Mode
)

$ErrorActionPreference = 'Stop'
$modePath = Join-Path $PSScriptRoot 'DebugUIView.mode'

function Get-CurrentMode {
    if (!(Test-Path -LiteralPath $modePath -PathType Leaf)) { return 'Web' }
    try {
        if ((Get-Content -Raw -LiteralPath $modePath).Trim() -ieq 'Native') { return 'Native' }
    } catch { }
    return 'Web'
}

if (!$PSBoundParameters.ContainsKey('Mode')) {
    Write-Host "Current UI: $(Get-CurrentMode)"
    Write-Host '1 - WebView2'
    Write-Host '2 - Native AutoHotkey windows'
    Write-Host '3 - Show current UI only'
    $choice = Read-Host 'Choose 1, 2 or 3'
    $Mode = switch ($choice) {
        '1' { 'Web' }
        '2' { 'Native' }
        '3' { 'Status' }
        default { throw 'Invalid choice. No changes were made.' }
    }
}

switch ($Mode) {
    'Native' {
        Set-Content -LiteralPath $modePath -Value 'Native' -Encoding Ascii -NoNewline
    }
    'Web' {
        if (Test-Path -LiteralPath $modePath) { Remove-Item -LiteralPath $modePath -Force }
    }
}

$current = Get-CurrentMode
Write-Host "UI for this Layout Toolkit copy: $current"
if ($Mode -ne 'Status') {
    Write-Host 'Close the Settings or Unicode Input window and open it again.'
    Write-Host 'Restarting Layout Toolkit is not required.'
}
