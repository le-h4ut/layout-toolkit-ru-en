; Installer probes must exit before normal startup touches profiles or hotkeys.
LTHealth_Run() {
    global g_ExcludeWords := Map()
    A_IconHidden := true
    try {
        required := ["Run_Layout_Toolkit.cmd", "Resolve_AutoHotkey.ps1", "install.ps1",
            "Manage_Startup.ps1", "Assets\hotkeys.default.ini", "Assets\exclude.default.txt"]
        for page, prefix in Map("WebSettings", "settings", "WebUnicodeInput", "unicode", "WebWelcome", "welcome") {
            for name in ["index.html", prefix ".css", prefix ".js"]
                required.Push("Assets\" page "\" name)
        }
        required.Push("Modules\Vendor\WebView2\" (A_PtrSize = 8 ? "64bit" : "32bit") "\WebView2Loader.dll")
        for relativePath in required {
            path := A_ScriptDir "\" relativePath
            if !FileExist(path) || FileGetSize(path) = 0
                throw Error("Missing or empty release file: " relativePath)
        }
        if !(ConvertFullText("Ghbdtn vbh") == "Привет мир")
            throw Error("Full conversion smoke check failed")
        if !(ConvertToMajority("Привет мир Ghbdtn") == "Привет мир Привет")
            throw Error("Majority conversion smoke check failed")
        if !(UnicodeInput_CodesToText(UnicodeInput_ParseCodes("2014")) == "—")
            throw Error("Unicode parser smoke check failed")
        if JSON.parse('{"ready":true}')["ready"] != 1
            throw Error("JSON parser smoke check failed")
        FileAppend("LAYOUT_TOOLKIT_HEALTH_OK`n", "*", "UTF-8")
        ExitApp(0)
    } catch as err {
        FileAppend("Health check failed: " err.Message "`n", "**", "UTF-8")
        ExitApp(1)
    }
}

LTHealth_PrepareStartupCheck() {
    global g_LTReadyFile := "", g_LTReadyToken := ""
    for index, arg in A_Args {
        if arg = "--ready-file" && index < A_Args.Length
            g_LTReadyFile := A_Args[index + 1]
        if arg = "--ready-token" && index < A_Args.Length
            g_LTReadyToken := A_Args[index + 1]
    }
    if g_LTReadyFile != "" && g_LTReadyToken != "" {
        SplitPath(g_LTReadyFile, , &directory)
        ; A later Reload may retain installer arguments after its temporary folder is gone.
        if !DirExist(directory) {
            g_LTReadyFile := ""
            g_LTReadyToken := ""
            return
        }
        OnError(LTHealth_StartupError)
    }
}

LTHealth_WriteReady(success, reason := "") {
    global g_LTReadyFile, g_LTReadyToken
    report := Map("protocol", 1, "token", g_LTReadyToken, "pid", ProcessExist(),
        "scriptPath", A_ScriptFullPath, "ready", success ? JSON.true : JSON.false,
        "error", reason)
    temporary := g_LTReadyFile ".tmp-" ProcessExist()
    try {
        FileAppend(JSON.stringify(report), temporary, "UTF-8")
        FileMove(temporary, g_LTReadyFile, true)
    } finally {
        if FileExist(temporary)
            try FileDelete(temporary)
    }
}

LTHealth_StartupError(err, mode) {
    try LTHealth_WriteReady(false, err.Message)
    ExitApp(1)
}

LTHealth_ReportStartupReady() {
    global g_LTReadyFile, g_LTReadyToken, g_StartupHotkeysReady
    if g_LTReadyFile = "" || g_LTReadyToken = ""
        return
    if !g_StartupHotkeysReady {
        LTHealth_WriteReady(false, "Не удалось зарегистрировать горячие клавиши")
        ExitApp(1)
    }
    LTHealth_WriteReady(true)
    OnError(LTHealth_StartupError, 0)
}
