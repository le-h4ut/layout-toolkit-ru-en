[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [string]$InstallPath,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Update,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$NoAutostart,

    [Parameter(Mandatory, ParameterSetName = 'Uninstall')]
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$manifestUrl = 'https://raw.githubusercontent.com/ToPoR007/layout-toolkit-ru-en/main/latest.json'
$stateDir = Join-Path $env:LOCALAPPDATA 'Layout Toolkit'
$statePath = Join-Path $stateDir 'install.json'
$startupPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Layout Toolkit.lnk'

function Read-InstallState {
    if (!(Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json }
    catch { throw "Не удалось прочитать $statePath. Исправьте или удалите этот файл и повторите запуск." }
}

function Resolve-InstallPath([string]$RequestedPath, $State, [bool]$RequireExisting) {
    if ([string]::IsNullOrWhiteSpace($RequestedPath) -and $State -and $State.installPath) {
        $RequestedPath = [string]$State.installPath
    }
    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        if ($RequireExisting) { throw 'Установка не найдена. Сначала установите Layout Toolkit или укажите -InstallPath.' }
        $defaultPath = Join-Path $env:LOCALAPPDATA 'Programs\Layout Toolkit'
        $answer = Read-Host "Папка установки [$defaultPath]"
        $RequestedPath = if ([string]::IsNullOrWhiteSpace($answer)) { $defaultPath } else { $answer }
    }
    $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($RequestedPath))
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.TrimEnd('\') -eq $root.TrimEnd('\')) { throw 'Нельзя устанавливать Layout Toolkit в корень диска.' }
    return $fullPath.TrimEnd('\')
}

function Remove-StartupShortcut {
    if (Test-Path -LiteralPath $startupPath) { Remove-Item -LiteralPath $startupPath -Force }
}

function Assert-SafeExistingInstall([string]$TargetPath) {
    if (!(Test-Path -LiteralPath $TargetPath)) { return }
    if (Test-Path -LiteralPath (Join-Path $TargetPath '.git')) {
        throw 'Нельзя устанавливать обновление поверх Git-репозитория.'
    }
    $entries = @(Get-ChildItem -LiteralPath $TargetPath -Force)
    if ($entries.Count -eq 0) { return }
    if (!(Test-Path -LiteralPath (Join-Path $TargetPath 'Layout_Toolkit_RU_EN.ahk') -PathType Leaf) -or
        !(Test-Path -LiteralPath (Join-Path $TargetPath 'Run_Layout_Toolkit.cmd') -PathType Leaf)) {
        throw "Папка $TargetPath не похожа на установленный Layout Toolkit. Выберите пустую папку."
    }
}

function Set-StartupShortcut([string]$TargetPath) {
    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($startupPath)
    $shortcut.TargetPath = Join-Path $TargetPath 'Run_Layout_Toolkit.cmd'
    $shortcut.WorkingDirectory = $TargetPath
    $iconPath = Join-Path $TargetPath 'Assets\icon.ico'
    if (Test-Path -LiteralPath $iconPath) { $shortcut.IconLocation = $iconPath }
    $shortcut.Save()
}

$state = Read-InstallState

if ($Uninstall) {
    $target = Resolve-InstallPath $InstallPath $state $true
    Assert-SafeExistingInstall $target
    Remove-StartupShortcut
    if (Test-Path -LiteralPath $target) {
        try { Remove-Item -LiteralPath $target -Recurse -Force }
        catch { throw "Не удалось удалить $target. Закройте Layout Toolkit и повторите команду удаления." }
    }
    if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
    Write-Host 'Layout Toolkit удалён. Пользовательские файлы в Documents\Layout Toolkit сохранены.' -ForegroundColor Green
    return
}

$target = Resolve-InstallPath $InstallPath $state ([bool]$Update)
Assert-SafeExistingInstall $target
$manifest = Invoke-RestMethod -Uri $manifestUrl
if ($manifest.schema_version -ne 1) { throw "Неподдерживаемая версия latest.json: $($manifest.schema_version)" }
$asset = $manifest.assets.windows
if (!$asset.url -or !$asset.sha256 -or !$asset.size) { throw 'latest.json не содержит полного описания Windows-архива.' }

$workDir = Join-Path ([IO.Path]::GetTempPath()) ('layout-toolkit-install-' + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $workDir 'LayoutToolkit.zip'
$extractPath = Join-Path $workDir 'extracted'
$backupPath = $target + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
$previousMoved = $false
$previousState = if (Test-Path -LiteralPath $statePath) { Get-Content -Raw -LiteralPath $statePath } else { $null }

try {
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    Write-Host "Скачивание Layout Toolkit $($manifest.version)..."
    Invoke-WebRequest -Uri $asset.url -OutFile $archivePath
    $file = Get-Item -LiteralPath $archivePath
    if ($file.Length -ne [int64]$asset.size) { throw "Размер архива не совпал: получено $($file.Length), ожидалось $($asset.size)." }
    $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
    if ($actualHash -ne ([string]$asset.sha256).ToUpperInvariant()) { throw 'SHA-256 архива не совпал. Установка остановлена.' }

    Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
    $mainScript = Get-ChildItem -LiteralPath $extractPath -Filter 'Layout_Toolkit_RU_EN.ahk' -File -Recurse | Select-Object -First 1
    if (!$mainScript) { throw 'В архиве не найден Layout_Toolkit_RU_EN.ahk.' }
    $payloadPath = $mainScript.Directory.FullName

    if (Test-Path -LiteralPath $target) {
        if (Test-Path -LiteralPath $backupPath) { throw "Резервная папка уже существует: $backupPath" }
        try { Move-Item -LiteralPath $target -Destination $backupPath }
        catch { throw "Не удалось подготовить обновление. Закройте Layout Toolkit и повторите команду.`n$($_.Exception.Message)" }
        $previousMoved = $true
    }

    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Move-Item -LiteralPath $payloadPath -Destination $target

    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $now = (Get-Date).ToUniversalTime().ToString('o')
    $installedAt = if ($state -and $state.installedAt) { [string]$state.installedAt } else { $now }
    [ordered]@{
        schemaVersion = 1
        installPath = $target
        installedVersion = [string]$manifest.version
        channel = [string]$manifest.channel
        installedAt = $installedAt
        updatedAt = $now
        autostart = !$NoAutostart
    } | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8

    if ($NoAutostart) { Remove-StartupShortcut } else { Set-StartupShortcut $target }
    if ($previousMoved -and (Test-Path -LiteralPath $backupPath)) { Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host "Layout Toolkit $($manifest.version) установлен в $target" -ForegroundColor Green
    Start-Process -FilePath (Join-Path $target 'Run_Layout_Toolkit.cmd') -WorkingDirectory $target
} catch {
    if ($previousMoved -and (Test-Path -LiteralPath $backupPath)) {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue }
        if (!(Test-Path -LiteralPath $target)) { Move-Item -LiteralPath $backupPath -Destination $target }
    }
    if ($null -ne $previousState) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
        Set-Content -LiteralPath $statePath -Value $previousState -Encoding UTF8
    } elseif (Test-Path -LiteralPath $statePath) {
        Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
    }
    throw
} finally {
    if (Test-Path -LiteralPath $workDir) { Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue }
}
