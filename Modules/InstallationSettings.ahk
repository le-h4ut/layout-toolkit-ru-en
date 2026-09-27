; Installation controls shared by the WebView and native settings windows.
LTInstall_StatePath() {
    return EnvGet("LOCALAPPDATA") "\Layout Toolkit\install.json"
}

LTInstall_StartupPaths() {
    dir := A_Startup
    return [dir "\Layout Toolkit.lnk", dir "\Layout Toolkit RU-EN.lnk"]
}

LTInstall_SamePath(left, right) {
    if !left || !right
        return false
    return StrLower(RTrim(String(left), "\")) = StrLower(RTrim(String(right), "\"))
}

LTInstall_ShortcutIsCurrent(path) {
    if !FileExist(path)
        return false
    try {
        link := ComObject("WScript.Shell").CreateShortcut(path)
        launcher := A_ScriptDir "\Run_Layout_Toolkit.cmd"
        if LTInstall_SamePath(link.TargetPath, launcher)
            return true
        if LTInstall_SamePath(link.TargetPath, A_ScriptFullPath)
            return true
        ; Older shortcuts launch Resolve_AutoHotkey.ps1 with -ScriptPath.
        if !RegExMatch(link.TargetPath, "i)\\(?:powershell|autohotkey(?:64|32)?)(?:\.exe)?$")
            return false
        return InStr(StrLower(link.Arguments), StrLower(A_ScriptFullPath)) > 0
            && LTInstall_SamePath(link.WorkingDirectory, A_ScriptDir)
    } catch {
        return false
    }
}

LTInstall_StartupStatus(paths := 0) {
    if !IsObject(paths)
        paths := LTInstall_StartupPaths()
    owned := false, foreign := false
    for path in paths {
        if !FileExist(path)
            continue
        if LTInstall_ShortcutIsCurrent(path)
            owned := true
        else
            foreign := true
    }
    return Map("enabled", owned, "conflict", foreign)
}

LTInstall_ReadState() {
    path := LTInstall_StatePath()
    if !FileExist(path)
        return 0
    try {
        state := JSON.parse(FileRead(path, "UTF-8"))
        return state is Map ? state : 0
    } catch {
        return 0
    }
}

LTInstall_IsManaged(state) {
    return state is Map && state.Has("installPath")
        && LTInstall_SamePath(state["installPath"], A_ScriptDir)
        && FileExist(A_ScriptDir "\Run_Layout_Toolkit.cmd")
        && !FileExist(A_ScriptDir "\.git")
}

LTInstall_Status() {
    state := LTInstall_ReadState()
    startup := LTInstall_StartupStatus()
    managed := LTInstall_IsManaged(state)
    canUpdate := !FileExist(A_ScriptDir "\.git")
        && FileExist(A_ScriptDir "\Run_Layout_Toolkit.cmd")
        && FileExist(A_ScriptDir "\install.ps1")
    message := FileExist(A_ScriptDir "\.git")
        ? "Обновление Git-копии из программы отключено. Используйте Git."
        : !canUpdate ? "В этой копии отсутствуют файлы установщика. Обновите её установщиком вручную."
        : managed ? "" : "Установлено вручную. При первом обновлении эта копия будет зарегистрирована автоматически."
    return Map("managed", managed, "path", A_ScriptDir,
        "canUpdate", canUpdate ? true : false, "updateMessage", message,
        "autostart", startup["enabled"], "autostartConflict", startup["conflict"],
        "installedVersion", SettingsGui_GetVersionFromChangelog())
}

LTInstall_SaveAutostartState(enabled) {
    state := LTInstall_ReadState()
    if !LTInstall_IsManaged(state)
        return
    state["autostart"] := enabled ? JSON.true : JSON.false
    path := LTInstall_StatePath()
    temp := path ".tmp-" A_TickCount
    try {
        FileAppend(JSON.stringify(state), temp, "UTF-8")
        FileMove(temp, path, true)
    } finally {
        if FileExist(temp)
            FileDelete(temp)
    }
}

LTInstall_SetAutostart(enabled, paths := 0) {
    if !IsObject(paths)
        paths := LTInstall_StartupPaths()
    status := LTInstall_StartupStatus(paths)
    if enabled {
        if status["conflict"]
            throw Error("Автозагрузка уже содержит ярлык другой копии Layout Toolkit. Проверьте папку автозагрузки вручную.")
        if !FileExist(A_ScriptDir "\Run_Layout_Toolkit.cmd")
            throw Error("Файл запуска Run_Layout_Toolkit.cmd не найден.")
        link := ComObject("WScript.Shell").CreateShortcut(paths[1])
        link.TargetPath := A_ScriptDir "\Run_Layout_Toolkit.cmd"
        link.Arguments := ""
        link.WorkingDirectory := A_ScriptDir
        link.Description := "Layout Toolkit"
        icon := A_ScriptDir "\Assets\icon.ico"
        if FileExist(icon)
            link.IconLocation := icon
        link.Save()
    }
    for path in paths {
        if FileExist(path) && LTInstall_ShortcutIsCurrent(path) && (!enabled || path != paths[1])
            FileDelete(path)
    }
    LTInstall_SaveAutostartState(enabled)
    return LTInstall_Status()
}

LTInstall_OpenFolder() {
    Run('explorer.exe "' A_ScriptDir '"')
}

LTInstall_CompareVersions(left, right) {
    pattern := "i)^v?(\d+)\.(\d+)\.(\d+)(?:-beta\.(\d+))?$"
    if !RegExMatch(left, pattern, &a) || !RegExMatch(right, pattern, &b)
        return 0
    loop 3 {
        index := A_Index
        if Integer(a[index]) != Integer(b[index])
            return Integer(a[index]) > Integer(b[index]) ? 1 : -1
    }
    if a[4] = "" && b[4] != ""
        return 1
    if a[4] != "" && b[4] = ""
        return -1
    return Integer(a[4] = "" ? 0 : a[4]) > Integer(b[4] = "" ? 0 : b[4]) ? 1
        : Integer(a[4] = "" ? 0 : a[4]) < Integer(b[4] = "" ? 0 : b[4]) ? -1 : 0
}

LTInstall_EvaluateUpdate(manifest, current) {
    if !(manifest is Map) || manifest.Get("schema_version", 0) != 1
        throw Error("Неизвестный формат latest.json")
    version := String(manifest.Get("version", ""))
    if !RegExMatch(version, "i)^\d+\.\d+\.\d+(?:-beta\.\d+)?$")
        throw Error("Некорректная версия в latest.json")
    if !RegExMatch(current, "i)^v?\d+\.\d+\.\d+(?:-beta\.\d+)?$")
        throw Error("Неизвестна версия установленной копии")
    available := LTInstall_CompareVersions(version, current) > 0
    message := available ? "Доступна версия " version ". Установка начнётся только после подтверждения." : "Установлена актуальная версия " current "."
    return Map("available", available, "version", version, "message", message)
}

LTInstall_CheckUpdate() {
    status := LTInstall_Status()
    if !status["canUpdate"]
        return Map("available", false, "message", status["updateMessage"])
    try {
        manifest := LTInstall_FetchManifest()
        return LTInstall_EvaluateUpdate(manifest, status["installedVersion"])
    } catch as err {
        throw Error("Не удалось проверить обновления: " err.Message)
    }
}

LTInstall_FetchManifest() {
    request := ComObject("WinHttp.WinHttpRequest.5.1")
    request.SetTimeouts(3000, 3000, 5000, 5000)
    request.Open("GET", "https://raw.githubusercontent.com/le-h4ut/layout-toolkit-ru-en/main/latest.json", false)
    request.Send()
    if request.Status != 200
        throw Error("Сервер ответил кодом " request.Status)
    return JSON.parse(request.ResponseText)
}

LTInstall_BuildUpdateCommand(status) {
    if !status["canUpdate"]
        throw Error(status["updateMessage"])
    powershell := A_WinDir "\System32\WindowsPowerShell\v1.0\powershell.exe"
    command := '"' powershell '" -NoProfile -ExecutionPolicy Bypass -File "' A_ScriptDir '\install.ps1" -Update -InstallPath "' A_ScriptDir '" -WaitForPid ' ProcessExist()
    if !status["autostart"]
        command .= " -NoAutostart"
    return command
}

LTInstall_StartUpdate(checkedVersion) {
    status := LTInstall_Status()
    if !status["canUpdate"]
        throw Error(status["updateMessage"])
    script := A_ScriptDir "\install.ps1"
    if !FileExist(script)
        throw Error("В этой сборке нет install.ps1. Обновите её командой из README, затем кнопка станет доступна.")
    fresh := LTInstall_CheckUpdate()
    if !fresh["available"] || fresh["version"] != checkedVersion
        throw Error("Данные об обновлении изменились. Проверьте обновления ещё раз.")
    if MsgBox("Установить Layout Toolkit " checkedVersion "? Программа закроется на время обновления.", "Layout Toolkit", "YesNo Icon?") != "Yes"
        return false
    command := LTInstall_BuildUpdateCommand(status)
    ; Never hold the directory that the installer must rename for rollback.
    Run(command, A_WinDir)
    ExitApp()
}
