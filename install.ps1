[CmdletBinding(DefaultParameterSetName = 'Install')]
param(
    [Parameter(ParameterSetName = 'Install')]
    [string]$InstallPath,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$Update,

    [Parameter(ParameterSetName = 'Install')]
    [switch]$NoAutostart,

    [Parameter(ParameterSetName = 'Install')]
    [ValidateRange(0, 2147483647)]
    [int]$WaitForPid = 0,

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

function Enter-InstallerWorkingDirectory {
    # Set-Location alone does not release the native Windows current-directory
    # handle inherited from an older UI or a terminal inside the installation.
    $neutral = [Environment]::GetFolderPath('Windows')
    if (!(Test-Path -LiteralPath $neutral -PathType Container)) { throw 'Windows directory is unavailable.' }
    Set-Location -LiteralPath $neutral
    [IO.Directory]::SetCurrentDirectory($neutral)
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
    $selected = [IO.Path]::GetFullPath([string]$folder.Self.Path)
    if ($selected -ne [IO.Path]::GetPathRoot($selected)) { $selected = $selected.TrimEnd('\') }
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
    $directory = Get-Item -LiteralPath $TargetPath -Force
    if (!$directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'Папка установки не должна быть файлом или символической ссылкой.'
    }
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

function Ensure-InstallParent([string]$TargetPath) {
    $parent = Split-Path -Parent $TargetPath
    # Windows PowerShell 5.1 New-Item -Force fails for an existing drive root (for example D:\).
    if (!(Test-Path -LiteralPath $parent -PathType Container)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
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

function Wait-PreviousInstance([string]$SourcePath, [int]$ProcessId) {
    if ($ProcessId -gt 0) {
        $previous = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if ($previous -and !$previous.WaitForExit(15000)) {
            throw 'Предыдущая копия Layout Toolkit не закрылась. Закройте её и повторите обновление.'
        }
    }
    if (!(Test-InstallDirectory $SourcePath)) { return }
    $main = Join-Path $SourcePath 'Layout_Toolkit_RU_EN.ahk'
    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    } catch {
        throw 'Не удалось проверить запущенные копии Layout Toolkit. Обновление остановлено до замены файлов.'
    }
    $quoted = '"' + $main + '"'
    $unquotedPattern = '(?i)(?:^|\s)' + [regex]::Escape($main) + '(?:\s|$)'
    foreach ($item in $processes) {
        if ($item.CommandLine -and ($item.CommandLine.IndexOf($quoted, [StringComparison]::OrdinalIgnoreCase) -ge 0 -or
            $item.CommandLine -match $unquotedPattern)) {
            throw 'Эта копия Layout Toolkit ещё запущена. Закройте её и повторите обновление.'
        }
    }
}

function Resolve-InstallRuntime([string]$PayloadPath, [string]$WorkDir) {
    $resolver = Join-Path $PayloadPath 'Resolve_AutoHotkey.ps1'
    if (!(Test-Path -LiteralPath $resolver -PathType Leaf)) { throw 'В релизе отсутствует Resolve_AutoHotkey.ps1.' }
    $cache = Join-Path $WorkDir 'autohotkey-path.txt'
    $oldCache = Join-Path $stateDir 'autohotkey-path.txt'
    if (Test-Path -LiteralPath $oldCache -PathType Leaf) { Copy-Item -LiteralPath $oldCache -Destination $cache }
    $powershell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    & $powershell -NoProfile -ExecutionPolicy Bypass -File $resolver -Action Resolve -CachePath $cache
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $cache -PathType Leaf)) {
        throw 'AutoHotkey v2 не найден или его выбор отменён. Файлы установки не изменены.'
    }
    $runtime = ([IO.File]::ReadAllText($cache)).Trim()
    if (!(Test-Path -LiteralPath $runtime -PathType Leaf)) { throw 'Путь AutoHotkey v2 недоступен.' }
    return $runtime
}

function Stop-OwnedProcess($Process) {
    if ($null -ne $Process -and !$Process.HasExited) {
        $Process.Kill()
        if (!$Process.WaitForExit(5000)) { throw 'Не удалось остановить проверяемый процесс.' }
    }
}

function Invoke-ReleaseHealthCheck([string]$Runtime, [string]$PayloadPath, [string]$WorkDir, [int]$TimeoutMs = 15000) {
    $stdout = Join-Path $WorkDir 'health.stdout.txt'
    $stderr = Join-Path $WorkDir 'health.stderr.txt'
    $main = Join-Path $PayloadPath 'Layout_Toolkit_RU_EN.ahk'
    $warningDirective = Join-Path $WorkDir 'health-warnings.ahk'
    [IO.File]::WriteAllText($warningDirective, "#Warn VarUnset, StdOut`n#Warn Unreachable, StdOut`n", [Text.UTF8Encoding]::new($true))
    # /force disables single-instance replacement for this short-lived probe.
    $process = Start-Process -FilePath $Runtime -ArgumentList ('/force /ErrorStdOut=UTF-8 /include "{0}" "{1}" --health-check' -f $warningDirective, $main) -WorkingDirectory $PayloadPath -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
    $null = $process.Handle
    try {
        if (!$process.WaitForExit($TimeoutMs)) { throw 'Проверка релиза не завершилась вовремя.' }
        $process.Refresh()
        $outputText = [IO.File]::ReadAllText($stdout, [Text.Encoding]::UTF8).Trim()
        $errorText = [IO.File]::ReadAllText($stderr, [Text.Encoding]::UTF8).Trim()
        if ($process.ExitCode -ne 0 -or $outputText -ne 'LAYOUT_TOOLKIT_HEALTH_OK' -or $errorText) {
            throw "Новая версия не прошла --health-check (код $($process.ExitCode)). $outputText $errorText"
        }
    } finally {
        Stop-OwnedProcess $process
    }
}

function Assert-ReleaseHealthProtocol([string]$PayloadPath) {
    $main = Join-Path $PayloadPath 'Layout_Toolkit_RU_EN.ahk'
    if (!(Test-Path -LiteralPath (Join-Path $PayloadPath 'Modules\HealthCheck.ahk') -PathType Leaf) -or
        ([IO.File]::ReadAllText($main) -notmatch 'LTHealth_Run\(\)')) {
        throw 'Этот релиз не поддерживает безопасную проверку запуска. Установка остановлена; используйте совместимый релиз 1.5.0 или установите старую beta вручную.'
    }
}

function Start-ValidatedLayoutToolkit([string]$Runtime, [string]$TargetPath, [string]$WorkDir, [int]$TimeoutMs = 15000) {
    $readyPath = Join-Path $WorkDir 'startup-ready.json'
    if (Test-Path -LiteralPath $readyPath) { Remove-Item -LiteralPath $readyPath -Force }
    $token = [guid]::NewGuid().ToString('N')
    $main = Join-Path $TargetPath 'Layout_Toolkit_RU_EN.ahk'
    $process = Start-Process -FilePath $Runtime -ArgumentList ('/ErrorStdOut=UTF-8 "{0}" --ready-file "{1}" --ready-token {2}' -f $main, $readyPath, $token) -WorkingDirectory $TargetPath -WindowStyle Hidden -PassThru
    $null = $process.Handle
    try {
        $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
        while ([DateTime]::UtcNow -lt $deadline) {
            if (Test-Path -LiteralPath $readyPath -PathType Leaf) {
                $report = Get-Content -Raw -LiteralPath $readyPath | ConvertFrom-Json
                if ($report.protocol -ne 1 -or $report.token -cne $token -or $report.pid -ne $process.Id -or $report.scriptPath -ine $main) {
                    throw 'Новая версия вернула неверный ответ проверки запуска.'
                }
                if (!$report.ready) { throw "Новая версия не смогла запуститься: $($report.error)" }
                Start-Sleep -Milliseconds 500
                if ($process.HasExited) { throw 'Новая версия завершилась сразу после проверки запуска.' }
                return $process
            }
            if ($process.HasExited) { throw "Новая версия завершилась при запуске (код $($process.ExitCode))." }
            Start-Sleep -Milliseconds 50
        }
        throw 'Новая версия не подтвердила готовность вовремя.'
    } catch {
        $failure = $_.Exception
        try { Stop-OwnedProcess $process }
        catch {
            $stopFailure = [Exception]::new("Ошибка запуска: $($failure.Message). Не удалось остановить новый процесс: $($_.Exception.Message)", $failure)
            $stopFailure.Data['StartupProcess'] = $process
            throw $stopFailure
        }
        throw $failure
    }
}

function Test-OwnedStartupShortcut([string]$LinkPath, [string[]]$InstallPaths) {
    if (!(Test-Path -LiteralPath $LinkPath -PathType Leaf)) { return $false }
    $link = (New-Object -ComObject WScript.Shell).CreateShortcut($LinkPath)
    foreach ($path in $InstallPaths) {
        $main = Join-Path $path 'Layout_Toolkit_RU_EN.ahk'
        if ($link.TargetPath -ieq (Join-Path $path 'Run_Layout_Toolkit.cmd') -or $link.TargetPath -ieq $main) { return $true }
        if ($link.TargetPath -match '(?i)\\(?:powershell|autohotkey(?:64|32)?)\.exe$' -and
            $link.Arguments.IndexOf(('"' + $main + '"'), [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    return $false
}

function Save-InstallMetadataBackup([string]$WorkDir) {
    $snapshot = @()
    $index = 0
    foreach ($path in @($statePath, $startupPath, $legacyStartupPath, (Join-Path $stateDir 'autohotkey-path.txt'))) {
        $backup = Join-Path $WorkDir ('metadata-' + $index + '.bak')
        $exists = Test-Path -LiteralPath $path -PathType Leaf
        if ($exists) { Copy-Item -LiteralPath $path -Destination $backup }
        $snapshot += [pscustomobject]@{ Path = $path; Backup = $backup; Existed = $exists }
        $index++
    }
    return $snapshot
}

function Restore-InstallMetadataBackup($Snapshot) {
    foreach ($item in $Snapshot) {
        if ($item.Existed) {
            New-Item -ItemType Directory -Path (Split-Path -Parent $item.Path) -Force | Out-Null
            Copy-Item -LiteralPath $item.Backup -Destination $item.Path -Force
        } elseif (Test-Path -LiteralPath $item.Path -PathType Leaf) {
            Remove-Item -LiteralPath $item.Path -Force
        }
    }
}

function Write-InstallStateAtomic($Value) {
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    $temporary = Join-Path $stateDir ('install-' + [guid]::NewGuid().ToString('N') + '.tmp')
    $replaced = $temporary + '.old'
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
        if (Test-Path -LiteralPath $statePath -PathType Leaf) { [IO.File]::Replace($temporary, $statePath, $replaced) }
        else { [IO.File]::Move($temporary, $statePath) }
    } finally {
        if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary -Force }
        if (Test-Path -LiteralPath $replaced) { Remove-Item -LiteralPath $replaced -Force }
    }
}

function Invoke-InstallTransaction([string]$PayloadPath, [string]$SourcePath, [string]$TargetPath, [string]$Runtime, [string]$WorkDir, $Manifest, [bool]$DisableAutostart) {
    $SourcePath = Resolve-InstallPath $SourcePath '' $false
    $TargetPath = Resolve-InstallPath $TargetPath '' $false
    if ($TargetPath -ine $SourcePath -and $TargetPath -ine (Get-CanonicalUpdatePath $SourcePath)) { throw 'Небезопасный путь обновления.' }
    Assert-SafeExistingInstall $SourcePath
    Assert-CanonicalUpdateDestination $SourcePath $TargetPath
    $ownedStartup = Test-OwnedStartupShortcut $startupPath @($SourcePath, $TargetPath)
    $ownedLegacy = Test-OwnedStartupShortcut $legacyStartupPath @($SourcePath, $TargetPath)
    if (!$DisableAutostart -and (Test-Path -LiteralPath $startupPath) -and !$ownedStartup) {
        throw 'Ярлык автозагрузки принадлежит другой копии. Обновление не будет заменять его.'
    }
    $snapshot = @(Save-InstallMetadataBackup $WorkDir)
    $previousState = Read-InstallState
    $backupPath = $SourcePath + '.backup-' + [guid]::NewGuid().ToString('N')
    # Stage beside the destination: TEMP and the installation may be on different volumes.
    $stagePath = Join-Path (Split-Path -Parent $TargetPath) ('.layout-toolkit-staging-' + [guid]::NewGuid().ToString('N'))
    $previousMoved = $false
    $newInstalled = $false
    $stageOwned = $false
    $rollbackIncomplete = $false
    $started = $null
    try {
        Ensure-InstallParent $TargetPath
        New-Item -ItemType Directory -Path $stagePath | Out-Null
        $stageOwned = $true
        foreach ($entry in Get-ChildItem -LiteralPath $PayloadPath -Force) {
            Copy-Item -LiteralPath $entry.FullName -Destination $stagePath -Recurse
        }
        if (Test-Path -LiteralPath $SourcePath) {
            [IO.Directory]::Move($SourcePath, $backupPath)
            $previousMoved = $true
        }
        # Directory.Move fails instead of nesting the payload into an unexpected existing directory.
        [IO.Directory]::Move($stagePath, $TargetPath)
        $newInstalled = $true
        $started = Start-ValidatedLayoutToolkit $Runtime $TargetPath $WorkDir
        $now = [DateTime]::UtcNow.ToString('o')
        $installedAt = if ($previousState -and $previousState.PSObject.Properties['installedAt']) { [string]$previousState.installedAt } else { $now }
        Write-InstallStateAtomic ([ordered]@{
            schemaVersion = 1; installPath = $TargetPath; installedVersion = [string]$Manifest.version
            channel = [string]$Manifest.channel; installedAt = $installedAt; updatedAt = $now
            autostart = !$DisableAutostart
        })
        [IO.File]::WriteAllText((Join-Path $stateDir 'autohotkey-path.txt'), $Runtime, [Text.UTF8Encoding]::new($false))
        if ($DisableAutostart) { if ($ownedStartup) { Remove-StartupShortcut } }
        else { Set-StartupShortcut $TargetPath }
        if ($ownedLegacy) { Remove-LegacyStartupShortcut }
    } catch {
        $failure = $_.Exception
        if ($failure.Data.Contains('StartupProcess')) { $started = $failure.Data['StartupProcess'] }
        try {
            Stop-OwnedProcess $started
            if ($newInstalled -and (Test-Path -LiteralPath $TargetPath)) {
                [IO.Directory]::Move($TargetPath, $stagePath)
            }
            if ($previousMoved) { [IO.Directory]::Move($backupPath, $SourcePath) }
            Restore-InstallMetadataBackup $snapshot
            $failure.Data['RollbackComplete'] = $true
        } catch {
            $rollbackIncomplete = $true
            $recovery = [Exception]::new("Обновление не удалось: $($failure.Message). Автоматический откат не завершён: $($_.Exception.Message). Сохранены backup: $backupPath, staging: $stagePath и служебные файлы: $WorkDir", $failure)
            $recovery.Data['RollbackComplete'] = $false
            throw $recovery
        }
        throw
    } finally {
        if ($stageOwned -and !$rollbackIncomplete -and (Test-Path -LiteralPath $stagePath)) {
            try { Remove-Item -LiteralPath $stagePath -Recurse -Force }
            catch { Write-Warning "Не удалось удалить служебную папку: $stagePath" }
        }
    }
    # Commit is complete. Cleanup failure must not undo a working installation.
    if ($previousMoved -and (Test-Path -LiteralPath $backupPath)) {
        try { Remove-Item -LiteralPath $backupPath -Recurse -Force }
        catch { Write-Warning "Обновление завершено. Старый backup пока не удалось удалить: $backupPath" }
    }
    Write-Host "Layout Toolkit $($Manifest.version) установлен в $TargetPath" -ForegroundColor Green
}

function Invoke-InstallerMain {
    $previousLocation = (Get-Location).Path
    $previousNativeDirectory = [IO.Directory]::GetCurrentDirectory()
    Enter-InstallerWorkingDirectory
    $mutexName = 'Local\LayoutToolkitInstaller-' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $mutex = New-Object Threading.Mutex($false, $mutexName)
    $locked = $false
    $workDir = $null
    $sourceTarget = $null
    $keepRecovery = $false
    $canRestartPrevious = $false
    try {
        try { $locked = $mutex.WaitOne(0) }
        catch [Threading.AbandonedMutexException] { $locked = $true }
        if (!$locked) { throw 'Другой установщик Layout Toolkit уже работает. Дождитесь его завершения.' }

        $state = Read-InstallState
        $legacyInstallPath = if ($null -eq $state) { Find-LegacyInstall } else { $null }
        $detectedInstallPath = if ($state -and $state.PSObject.Properties['installPath']) { [string]$state.installPath } else { $legacyInstallPath }

        if ($Uninstall) {
            $target = Resolve-InstallPath $InstallPath $detectedInstallPath $true
            Assert-SafeExistingInstall $target
            Wait-PreviousInstance $target 0
            if (Test-OwnedStartupShortcut $startupPath @($target)) { Remove-StartupShortcut }
            if (Test-OwnedStartupShortcut $legacyStartupPath @($target)) { Remove-LegacyStartupShortcut }
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
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
        if ($Update) { $sourceTarget = Resolve-UpdateSourcePath $sourceTarget $target }
        Assert-SafeExistingInstall $sourceTarget
        Assert-CanonicalUpdateDestination $sourceTarget $target
        Wait-PreviousInstance $sourceTarget $WaitForPid
        $canRestartPrevious = $WaitForPid -gt 0 -and (Test-InstallDirectory $sourceTarget)

        $manifest = Invoke-RestMethod -Uri $manifestUrl
        if ($manifest.schema_version -ne 1) { throw "Неподдерживаемая версия latest.json: $($manifest.schema_version)" }
        $asset = $manifest.assets.windows
        if (!$asset.url -or $asset.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or [int64]$asset.size -le 0) {
            throw 'latest.json не содержит корректного описания Windows-архива.'
        }
        if ([uri]$asset.url -and ([uri]$asset.url).Scheme -ne 'https') { throw 'Архив релиза должен скачиваться по HTTPS.' }

        $workDir = Join-Path ([IO.Path]::GetTempPath()) ('layout-toolkit-install-' + [guid]::NewGuid().ToString('N'))
        $archivePath = Join-Path $workDir 'LayoutToolkit.zip'
        $extractPath = Join-Path $workDir 'extracted'
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        Write-Host "Скачивание Layout Toolkit $($manifest.version)..."
        Invoke-WebRequest -Uri $asset.url -OutFile $archivePath -UseBasicParsing
        $file = Get-Item -LiteralPath $archivePath
        if ($file.Length -ne [int64]$asset.size) { throw "Размер архива не совпал: получено $($file.Length), ожидалось $($asset.size)." }
        $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash
        if ($actualHash -ne ([string]$asset.sha256).ToUpperInvariant()) { throw 'SHA-256 архива не совпал. Установка остановлена.' }

        Expand-Archive -LiteralPath $archivePath -DestinationPath $extractPath -Force
        $mainScripts = @(Get-ChildItem -LiteralPath $extractPath -Filter 'Layout_Toolkit_RU_EN.ahk' -File -Recurse)
        if ($mainScripts.Count -ne 1) { throw 'В архиве должен быть ровно один Layout_Toolkit_RU_EN.ahk.' }
        $payloadPath = $mainScripts[0].Directory.FullName
        $links = @(Get-ChildItem -LiteralPath $extractPath -Recurse -Force | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint })
        if ($links.Count) { throw 'Архив содержит символические ссылки; установка остановлена.' }
        Assert-ReleaseHealthProtocol $payloadPath
        $runtime = Resolve-InstallRuntime $payloadPath $workDir
        Write-Host 'Проверка новой версии...'
        Invoke-ReleaseHealthCheck $runtime $payloadPath $workDir
        # Recheck after downloading and dependency selection: an old copy may have been started meanwhile.
        Wait-PreviousInstance $sourceTarget 0
        $disableAutostart = [bool]$NoAutostart
        if (!$NoAutostart -and $state -and $state.PSObject.Properties['autostart']) { $disableAutostart = !$state.autostart }
        Invoke-InstallTransaction $payloadPath $sourceTarget $target $runtime $workDir $manifest $disableAutostart
    } catch {
        $failure = $_.Exception
        # Preserve probe output before the temporary download directory is removed.
        if ($workDir -and $script:InstallerLogDirectory -and (Test-Path -LiteralPath $workDir)) {
            foreach ($name in @('health.stdout.txt','health.stderr.txt','startup.stdout.txt','startup.stderr.txt','startup-ready.json')) {
                $diagnostic = Join-Path $workDir $name
                if (Test-Path -LiteralPath $diagnostic -PathType Leaf) {
                    try { Copy-Item -LiteralPath $diagnostic -Destination $script:InstallerLogDirectory -Force }
                    catch { Write-Warning "Diagnostic copy failed: $diagnostic" }
                }
            }
        }
        $keepRecovery = $failure.Data.Contains('RollbackComplete') -and !$failure.Data['RollbackComplete']
        if ($canRestartPrevious -and !$keepRecovery -and $sourceTarget -and (Test-InstallDirectory $sourceTarget)) {
            try {
                Wait-PreviousInstance $sourceTarget 0
                Start-Process -FilePath (Join-Path $sourceTarget 'Run_Layout_Toolkit.cmd') -WorkingDirectory $sourceTarget -WindowStyle Hidden
                Write-Warning 'Обновление не завершено. Предыдущая версия сохранена и запущена повторно.'
            } catch { Write-Warning "Предыдущая версия сохранена, но её нужно запустить вручную: $sourceTarget" }
        }
        throw
    } finally {
        if ($workDir -and !$keepRecovery -and (Test-Path -LiteralPath $workDir)) {
            Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
        if (Test-Path -LiteralPath $previousLocation -PathType Container) { Set-Location -LiteralPath $previousLocation }
        if (Test-Path -LiteralPath $previousNativeDirectory -PathType Container) { [IO.Directory]::SetCurrentDirectory($previousNativeDirectory) }
    }
}

function Invoke-InstallerWithDiagnostics {
    $script:InstallerLogDirectory = $null
    $transcribing = $false
    $previousLocation = (Get-Location).Path
    $previousNativeDirectory = [IO.Directory]::GetCurrentDirectory()
    try {
        Enter-InstallerWorkingDirectory
        $script:InstallerLogDirectory = Join-Path $stateDir ('Logs\install-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $script:InstallerLogDirectory -Force | Out-Null
        Start-Transcript -LiteralPath (Join-Path $script:InstallerLogDirectory 'installer.log') -Force | Out-Null
        $transcribing = $true
        Invoke-InstallerMain
    } catch {
        $failure = $_
        $errorLog = if ($script:InstallerLogDirectory) { Join-Path $script:InstallerLogDirectory 'error.txt' } else { '' }
        if ($errorLog) {
            try { [IO.File]::WriteAllText($errorLog, ($failure | Format-List * -Force | Out-String), [Text.UTF8Encoding]::new($true)) }
            catch { Write-Warning 'Unable to save installer error log.' }
        }
        if ($WaitForPid -gt 0) {
            try {
                Add-Type -AssemblyName System.Windows.Forms
                $null = [System.Windows.Forms.MessageBox]::Show(
                    "Обновление не завершено.`n`n$($failure.Exception.Message)`n`nДиагностика: $errorLog",
                    'Layout Toolkit — обновление', [System.Windows.Forms.MessageBoxButtons]::OK,
                    [System.Windows.Forms.MessageBoxIcon]::Error)
            } catch { Write-Warning 'Unable to show installer error window.' }
        }
        throw
    } finally {
        if ($transcribing) { Stop-Transcript | Out-Null }
        # Do not re-enter a directory that no longer exists after migration.
        if (Test-Path -LiteralPath $previousLocation -PathType Container) { Set-Location -LiteralPath $previousLocation }
        if (Test-Path -LiteralPath $previousNativeDirectory -PathType Container) { [IO.Directory]::SetCurrentDirectory($previousNativeDirectory) }
    }
}

$script:InstallerLogDirectory = $null
Invoke-InstallerWithDiagnostics
