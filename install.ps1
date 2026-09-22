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

$manifestUrl = 'https://raw.githubusercontent.com/le-h4ut/layout-toolkit-ru-en/main/latest.json'
$stateDir = Join-Path $env:LOCALAPPDATA 'Layout Toolkit'
$statePath = Join-Path $stateDir 'install.json'
$startupPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Layout Toolkit.lnk'
$legacyStartupPath = Join-Path ([Environment]::GetFolderPath('Startup')) 'Layout Toolkit RU-EN.lnk'

function Read-InstallState {
    if (!(Test-Path -LiteralPath $statePath -PathType Leaf)) { return $null }
    try { return Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json }
    catch { throw "Не удалось прочитать $statePath. Исправьте или удалите этот файл и повторите запуск." }
}

function Test-InstallDirectory([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return (Test-Path -LiteralPath (Join-Path $Path 'Layout_Toolkit_RU_EN.ahk') -PathType Leaf) -and
           (Test-Path -LiteralPath (Join-Path $Path 'Run_Layout_Toolkit.cmd') -PathType Leaf)
}

function Find-LegacyInstall {
    if (!(Test-Path -LiteralPath $legacyStartupPath -PathType Leaf)) { return $null }
    try {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($legacyStartupPath)
        $candidates = [Collections.Generic.List[string]]::new()
        if (![string]::IsNullOrWhiteSpace($shortcut.WorkingDirectory)) {
            $candidates.Add([Environment]::ExpandEnvironmentVariables($shortcut.WorkingDirectory))
        }
        if (![string]::IsNullOrWhiteSpace($shortcut.TargetPath)) {
            $targetPath = [Environment]::ExpandEnvironmentVariables($shortcut.TargetPath)
            $candidates.Add((Split-Path -Parent $targetPath))
        }
        $arguments = [Environment]::ExpandEnvironmentVariables([string]$shortcut.Arguments)
        foreach ($match in [regex]::Matches($arguments, '(?i)(?:"(?<path>[^"]*Layout_Toolkit_RU_EN\.ahk)"|(?<path>[^\s"]*Layout_Toolkit_RU_EN\.ahk))')) {
            $candidates.Add((Split-Path -Parent $match.Groups['path'].Value))
        }
        foreach ($candidate in $candidates | Select-Object -Unique) {
            if (Test-InstallDirectory $candidate) { return [IO.Path]::GetFullPath($candidate).TrimEnd('\') }
        }
    } catch {
        return $null
    }
    return $null
}

function Select-InteractiveInstallPath {
    $shell = New-Object -ComObject Shell.Application
    $folder = $shell.BrowseForFolder(0, 'Выберите папку для установки Layout Toolkit', 0x41)
    if ($null -eq $folder -or $null -eq $folder.Self -or [string]::IsNullOrWhiteSpace($folder.Self.Path)) { return $null }
    $selected = [IO.Path]::GetFullPath([string]$folder.Self.Path).TrimEnd('\')
    if ([IO.Path]::GetFileName($selected) -ieq 'Layout Toolkit') { return $selected }

    Add-Type -AssemblyName PresentationFramework
    $choice = [System.Windows.MessageBox]::Show(
        "Создать внутри выбранной папки подпапку «Layout Toolkit»?`n`nДа — установить в подпапку.`nНет — установить прямо в выбранную папку (она должна быть пустой).",
        'Layout Toolkit — установка',
        [System.Windows.MessageBoxButton]::YesNoCancel,
        [System.Windows.MessageBoxImage]::Question)
    if ($choice -eq [System.Windows.MessageBoxResult]::Cancel) { return $null }
    if ($choice -eq [System.Windows.MessageBoxResult]::Yes) { return Join-Path $selected 'Layout Toolkit' }
    return $selected
}

function Resolve-InstallPath([string]$RequestedPath, [string]$DetectedPath, [bool]$RequireExisting) {
    if ([string]::IsNullOrWhiteSpace($RequestedPath) -and ![string]::IsNullOrWhiteSpace($DetectedPath)) {
        $RequestedPath = $DetectedPath
    }
    if ([string]::IsNullOrWhiteSpace($RequestedPath)) {
        if ($RequireExisting) {
            throw 'Установка не найдена ни по install.json, ни по старому ярлыку автозагрузки. Передайте -InstallPath с путём к установленному Layout Toolkit.'
        }
        $RequestedPath = Select-InteractiveInstallPath
        if ([string]::IsNullOrWhiteSpace($RequestedPath)) { return $null }
    }
    $fullPath = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($RequestedPath))
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.TrimEnd('\') -eq $root.TrimEnd('\')) { throw 'Нельзя устанавливать Layout Toolkit в корень диска.' }
    return $fullPath.TrimEnd('\')
}

function Get-CanonicalUpdatePath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $leaf = [IO.Path]::GetFileName($fullPath)
    if ($leaf -notmatch '(?i)^Layout Toolkir(?: Ru En)?$') { return $fullPath }
    $correctedLeaf = [regex]::Replace($leaf, '(?i)Toolkir', 'Toolkit')
    return Join-Path (Split-Path -Parent $fullPath) $correctedLeaf
}

function Resolve-UpdateSourcePath([string]$SourcePath, [string]$CanonicalPath) {
    if ($SourcePath -ne $CanonicalPath -and !(Test-Path -LiteralPath $SourcePath) -and
        (Test-InstallDirectory $CanonicalPath)) {
        return $CanonicalPath
    }
    return $SourcePath
}

function Assert-CanonicalUpdateDestination([string]$SourcePath, [string]$CanonicalPath) {
    if ($SourcePath -ne $CanonicalPath -and (Test-Path -LiteralPath $CanonicalPath)) {
        throw "Не удалось исправить имя папки: $CanonicalPath уже существует. Освободите этот путь и повторите обновление."
    }
}

function Remove-StartupShortcut {
    if (Test-Path -LiteralPath $startupPath) { Remove-Item -LiteralPath $startupPath -Force }
}

function Remove-LegacyStartupShortcut {
    if (Test-Path -LiteralPath $legacyStartupPath) { Remove-Item -LiteralPath $legacyStartupPath -Force -ErrorAction SilentlyContinue }
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
$legacyInstallPath = if ($null -eq $state) { Find-LegacyInstall } else { $null }
$detectedInstallPath = if ($state -and $state.installPath) { [string]$state.installPath } else { $legacyInstallPath }
$usingLegacyInstall = $null -eq $state -and
                      ![string]::IsNullOrWhiteSpace($legacyInstallPath) -and
                      [string]::IsNullOrWhiteSpace($InstallPath)

if ($Uninstall) {
    $target = Resolve-InstallPath $InstallPath $detectedInstallPath $true
    Assert-SafeExistingInstall $target
    Remove-StartupShortcut
    if ($usingLegacyInstall) { Remove-LegacyStartupShortcut }
    if (Test-Path -LiteralPath $target) {
        try { Remove-Item -LiteralPath $target -Recurse -Force }
        catch { throw "Не удалось удалить $target. Закройте Layout Toolkit и повторите команду удаления." }
    }
    if (Test-Path -LiteralPath $statePath) { Remove-Item -LiteralPath $statePath -Force }
    Write-Host 'Layout Toolkit удалён. Пользовательские файлы в Documents\Layout Toolkit сохранены.' -ForegroundColor Green
    return
}

$sourceTarget = Resolve-InstallPath $InstallPath $detectedInstallPath ([bool]$Update)
if ([string]::IsNullOrWhiteSpace($sourceTarget)) {
    Write-Host 'Установка отменена. Изменения не вносились.' -ForegroundColor Yellow
    return
}
$target = if ($Update) { Get-CanonicalUpdatePath $sourceTarget } else { $sourceTarget }

# Релизы 1.4.1 и 1.5.0-beta.1 могли быть распакованы в папку с опечаткой
# Toolkir. При обновлении источник остаётся старым путём, а новая версия
# устанавливается по исправленному пути. Rollback возвращает старое имя.
if ($Update) { $sourceTarget = Resolve-UpdateSourcePath $sourceTarget $target }
Assert-SafeExistingInstall $sourceTarget
Assert-CanonicalUpdateDestination $sourceTarget $target
$manifest = Invoke-RestMethod -Uri $manifestUrl
if ($manifest.schema_version -ne 1) { throw "Неподдерживаемая версия latest.json: $($manifest.schema_version)" }
$asset = $manifest.assets.windows
if (!$asset.url -or !$asset.sha256 -or !$asset.size) { throw 'latest.json не содержит полного описания Windows-архива.' }

$workDir = Join-Path ([IO.Path]::GetTempPath()) ('layout-toolkit-install-' + [guid]::NewGuid().ToString('N'))
$archivePath = Join-Path $workDir 'LayoutToolkit.zip'
$extractPath = Join-Path $workDir 'extracted'
$backupPath = $sourceTarget + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
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

    if (Test-Path -LiteralPath $sourceTarget) {
        if (Test-Path -LiteralPath $backupPath) { throw "Резервная папка уже существует: $backupPath" }
        try { Move-Item -LiteralPath $sourceTarget -Destination $backupPath }
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

    if ($NoAutostart) {
        Remove-StartupShortcut
    } else {
        Set-StartupShortcut $target
    }
    Write-Host "Layout Toolkit $($manifest.version) установлен в $target" -ForegroundColor Green
    Start-Process -FilePath (Join-Path $target 'Run_Layout_Toolkit.cmd') -WorkingDirectory $target
    if ($usingLegacyInstall) { Remove-LegacyStartupShortcut }
    if ($previousMoved -and (Test-Path -LiteralPath $backupPath)) { Remove-Item -LiteralPath $backupPath -Recurse -Force -ErrorAction SilentlyContinue }
} catch {
    if ($usingLegacyInstall) { Remove-StartupShortcut }
    if ($previousMoved -and (Test-Path -LiteralPath $backupPath)) {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force -ErrorAction SilentlyContinue }
        if (!(Test-Path -LiteralPath $sourceTarget)) { Move-Item -LiteralPath $backupPath -Destination $sourceTarget }
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
