$ErrorActionPreference = 'Stop'
$source = Join-Path (Split-Path $PSScriptRoot -Parent) 'Assets\DebugUIView.ps1'
$windowsPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$tempDir = Join-Path ([IO.Path]::GetTempPath()) ('lt-debug-ui-' + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    $script = Join-Path $tempDir 'DebugUIView.ps1'
    $marker = Join-Path $tempDir 'DebugUIView.mode'
    Copy-Item -LiteralPath $source -Destination $script
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $script -Mode Status | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Windows PowerShell could not read the debug switch.' }
    if (Test-Path -LiteralPath $marker) { throw 'Status unexpectedly changed the mode.' }
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $script -Mode Native | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Windows PowerShell could not enable Native mode.' }
    if ((Get-Content -Raw -LiteralPath $marker).Trim() -ne 'Native') { throw 'Native mode was not saved.' }
    if ((Get-Item -LiteralPath $marker).Length -ne 6) { throw 'Native marker must not contain a line ending.' }
    & $windowsPowerShell -NoProfile -ExecutionPolicy Bypass -File $script -Mode Web | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Windows PowerShell could not restore Web mode.' }
    if (Test-Path -LiteralPath $marker) { throw 'Web mode did not restore the default.' }
    Write-Output 'PASS: debug UI switch changes only its own copy-local marker'
} finally {
    if (Test-Path -LiteralPath (Join-Path $tempDir 'DebugUIView.mode')) { Remove-Item -LiteralPath (Join-Path $tempDir 'DebugUIView.mode') -Force }
    if (Test-Path -LiteralPath (Join-Path $tempDir 'DebugUIView.ps1')) { Remove-Item -LiteralPath (Join-Path $tempDir 'DebugUIView.ps1') -Force }
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir }
}
