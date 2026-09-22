; Appended to an isolated production runtime by Run-WebSettingsTests.ps1.
WebTest_Assert(condition, label) {
    if !condition
        throw Error("FAIL: " label)
}

WebTest_StartSettingsLifecycle() {
    global g_WebTestSawLoading := false
    global g_WebTestSettingsPhase := 1
    global g_WebTestSettingsDeadline := A_TickCount + 15000
    global g_WebTestFirstSettingsWindow := 0
    SetTimer(WebTest_ObserveSettingsLoading, 10)
    LTWebSettings.Open()
    SetTimer(WebTest_SettingsLifecycleRun, -100)
}

WebTest_ObserveSettingsLoading() {
    global g_WebTestSawLoading
    if LTWebSettings.LoadingWindow && DllCall("IsWindowVisible", "Ptr", LTWebSettings.LoadingWindow.Hwnd, "Int") {
        g_WebTestSawLoading := true
        if !LTWebSettings.Ready && LTWebSettings.Window && DllCall("IsWindowVisible", "Ptr", LTWebSettings.Window.Hwnd, "Int")
            throw Error("Settings window became visible before the UI was ready")
    }
}

WebTest_SettingsLifecycleRun() {
    global g_WebTestSawLoading, g_WebTestSettingsPhase, g_WebTestSettingsDeadline, g_WebTestFirstSettingsWindow
    try {
        if !LTWebSettings.Ready || LTWebSettings.LoadingWindow {
            if A_TickCount > g_WebTestSettingsDeadline
                throw Error("Settings did not finish loading in phase " g_WebTestSettingsPhase)
            SetTimer(WebTest_SettingsLifecycleRun, -100)
            return
        }
        WebTest_Assert(DllCall("IsWindowVisible", "Ptr", LTWebSettings.Window.Hwnd, "Int"), "ready settings window is visible")
        WebTest_Assert(LTWebSettings.Controller.IsVisible, "hidden WebView controller becomes visible")
        if g_WebTestSettingsPhase = 1 {
            WebTest_Assert(g_WebTestSawLoading, "loading window was visible")
            g_WebTestFirstSettingsWindow := LTWebSettings.Window.Hwnd
            WinClose("ahk_id " g_WebTestFirstSettingsWindow)
            Sleep(100)
            WebTest_Assert(!LTWebSettings.Window && !LTWebSettings.Controller && !LTWebSettings.Core, "close releases WebView and HWND")
            g_WebTestSettingsPhase := 2
            g_WebTestSettingsDeadline := A_TickCount + 15000
            LTWebSettings.Open()
            SetTimer(WebTest_SettingsLifecycleRun, -100)
            return
        }
        WebTest_Assert(LTWebSettings.Window.Hwnd != g_WebTestFirstSettingsWindow, "reopen uses a new HWND")
        LTWebSettings.Dispose()
        LTWebSettings.Requested := true
        LTWebSettings.ShowLoading()
        WinClose("ahk_id " LTWebSettings.LoadingWindow.Hwnd)
        Sleep(100)
        WebTest_Assert(!LTWebSettings.Requested && !LTWebSettings.LoadingWindow, "loading can be cancelled")
        FileAppend("PASS: loading window, ready-only reveal, close, fresh reopen and loading cancellation`n", "*", "UTF-8")
        ExitApp(0)
    } catch as err {
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
        LTWebSettings.Dispose()
        ExitApp(1)
    }
}

WebTest_StartWelcomeBrowser() {
    LTWebWelcome.Open(true)
    SetTimer(WebTest_WelcomeBrowserRun, -100)
}

WebTest_WelcomeBrowserRun() {
    global g_ConfigPath
    try {
        deadline := A_TickCount + 20000
        while !LTWebWelcome.Ready {
            if A_TickCount > deadline
                throw Error("Welcome page did not become ready: " LTWebWelcome.LastError)
            Sleep(100)
        }
        core := LTWebWelcome.Core
        deadline := A_TickCount + 10000
        loop {
            value := core.ExecuteScriptAsync("document.querySelector('#layout-full').textContent !== '—'").await2(3000)
            if value = "true"
                break
            if A_TickCount > deadline
                throw Error("Welcome state did not render")
            Sleep(100)
        }
        rawMetrics := core.ExecuteScriptAsync("({scroll:document.documentElement.scrollHeight>innerHeight,columns:getComputedStyle(document.querySelector('.grid')).gridTemplateColumns,firstRun:document.querySelector('#save').textContent,checked:document.querySelector('#enable-live').checked})").await2(3000)
        metrics := JSON.parse(rawMetrics)
        WebTest_Assert(!metrics["scroll"], "welcome fits without scrolling")
        WebTest_Assert(metrics["firstRun"] = "Начать", "first-run action label")
        stream := WebView2.CreateFileStream(A_ScriptDir "\welcome.png", "w")
        core.CapturePreviewAsync(0, stream).await2(5000)
        stream := 0
        LTWebWelcome.Dispatch(Map("command", "close"))
        WebTest_Assert(IniRead(g_ConfigPath, "General", "FirstRunDone", "0") = "0", "closing first run leaves it pending")
        LTWebSettings.SaveTheme(Map("theme", "Dark"))
        LTWebWelcome.Open(false)
        Sleep(150)
        WebTest_Assert(core.ExecuteScriptAsync("document.querySelector('#save').textContent").await2(3000) = '"Сохранить"', "tray action label")
        WebTest_Assert(core.ExecuteScriptAsync("document.documentElement.dataset.theme").await2(3000) = '"dark"', "welcome follows saved dark theme")
        LTWebWelcome.Window.Show("w650 h440")
        Sleep(100)
        WebTest_Assert(core.ExecuteScriptAsync("document.documentElement.scrollHeight > innerHeight").await2(3000) = "false", "minimum window height needs no scrolling")
        stream := WebView2.CreateFileStream(A_ScriptDir "\welcome-dark.png", "w")
        core.CapturePreviewAsync(0, stream).await2(5000)
        stream := 0
        LTWebWelcome.Dispose()
        FileAppend("PASS: welcome WebView2, compact layout, first-run close and tray reopen`n", "*", "UTF-8")
        ExitApp(0)
    } catch as err {
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
        LTWebWelcome.Dispose()
        ExitApp(1)
    }
}

WebTest_Run() {
    global g_ConfigPath, g_HotkeysPath, g_HotkeyLayoutFull, g_HotkeyLiveConvert, g_RegisteredLiveConvertHotkey
    try {
        state := LTWebSettings.State()
        WebTest_Assert(state["version"] = "v1.5.0-beta.1", "Unreleased changelog section does not replace the installed version")
        WebTest_Assert(state["hotkeys"].Length = 7, "seven hotkey actions")
        WebTest_Assert(InStr(state["dataDir"], "UserData"), "isolated profile")
        frame := Gui()
        frame.Show("Hide w320 h200")
        WebTest_Assert(LTApplyWindowTheme(frame.Hwnd, "Dark"), "native DWM dark frame applied")
        WebTest_Assert(LTApplyWindowTheme(frame.Hwnd, "Light"), "native DWM light frame restored")
        frame.Destroy()
        WebTest_Assert(state["theme"] = "Light", "light theme defaults safely")
        WebTest_Assert(!state["live"]["switchInputLanguage"], "missing Live layout switch setting defaults to off")
        result := LTWebSettings.SaveTheme(Map("theme", "Dark"))
        WebTest_Assert(result["theme"] = "Dark" && LTWebSettings.State()["theme"] = "Dark", "dark theme persisted")
        rejected := false
        try LTWebSettings.SaveTheme(Map("theme", "Unknown"))
        catch
            rejected := true
        WebTest_Assert(rejected && LTWebSettings.State()["theme"] = "Dark", "invalid theme rejected")
        LTWebSettings.SaveTheme(Map("theme", "Light"))
        data := JSON.parse('{"enabled":true,"trigger":"Hotkey","interval":550,"switchInputLanguage":true,"hint":true}')
        LTWebSettings.SaveLive(data)
        WebTest_Assert(IniRead(g_ConfigPath, "General", "DoubleSpaceMs") = 550, "live interval saved")
        WebTest_Assert(IniRead(g_ConfigPath, "General", "LiveSwitchInputLanguage") = 1, "Live layout switch saved")
        WebTest_Assert(LTWebSettings.State()["live"]["switchInputLanguage"], "Live layout switch applied at runtime")
        WebTest_Assert(LTWebSettings.State()["live"]["trigger"] = "Hotkey", "runtime live mode updated")
        WebTest_Assert(g_RegisteredLiveConvertHotkey = g_HotkeyLiveConvert, "Live hotkey registered in Hotkey trigger mode")
        before := FileRead(g_ConfigPath)
        data["interval"] := 99
        rejected := false
        try LTWebSettings.SaveLive(data)
        catch
            rejected := true
        WebTest_Assert(rejected && FileRead(g_ConfigPath) == before, "invalid interval is not persisted")
        data := Map("confirm", 1, "moveHistory", 0, "history", "Alt", "favorite", "Ctrl")
        LTWebSettings.SaveUnicode(data)
        WebTest_Assert(LTWebSettings.State()["unicode"]["history"] = "Alt", "unicode setting applied")
        data["favorite"] := "Alt"
        rejected := false
        try LTWebSettings.SaveUnicode(data)
        catch
            rejected := true
        WebTest_Assert(rejected, "duplicate unicode modifier rejected")
        keys := SettingsGui_GetCurrentHotkeyValues()
        keys["LayoutFull"] := "^."
        keys["LiveConvert"] := "^!F9"
        LTWebSettings.SaveHotkeys(keys)
        WebTest_Assert(g_HotkeyLayoutFull == "^.", "punctuation shortcut accepted")
        WebTest_Assert(g_HotkeyLiveConvert == "^!F9", "second shortcut applied")
        before := FileRead(g_HotkeysPath)
        keys["LayoutMajority"] := "^."
        rejected := false
        try LTWebSettings.SaveHotkeys(keys)
        catch
            rejected := true
        WebTest_Assert(rejected && FileRead(g_HotkeysPath) == before, "duplicate hotkey rejected")
        before := FileRead(g_ConfigPath)
        rejected := false
        try LTWebSettings.WriteIni(g_ConfigPath, [["General", "DoubleSpaceMs", 1234]], WebTest_Fail, WebTest_NoOp)
        catch
            rejected := true
        WebTest_Assert(rejected && FileRead(g_ConfigPath) == before, "failed apply rolls back INI")
        welcome := LTWebWelcome.State()
        WebTest_Assert(welcome["layoutFull"] = HotkeyToDisplay(g_HotkeyLayoutFull), "welcome uses current shortcuts")
        LTWebWelcome.Window := Gui()
        LTWebWelcome.FirstRun := true
        LTWebWelcome.Dispatch(Map("command", "close"))
        WebTest_Assert(IniRead(g_ConfigPath, "General", "FirstRunDone", "0") = "0", "welcome close keeps first run pending")
        LTWebWelcome.Window := Gui()
        LTWebWelcome.FirstRun := true
        LTWebWelcome.Dispatch(Map("command", "save", "live", false))
        WebTest_Assert(IniRead(g_ConfigPath, "General", "FirstRunDone", "0") = "1", "welcome save completes first run")
        LTWebWelcome.Dispose()
        FileAppend("PASS: state, Live, Unicode, hotkeys, welcome save/close and INI rollback`n", "*", "UTF-8")
        ExitApp(0)
    } catch as err {
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
        ExitApp(1)
    }
}

WebTest_Fail(*) {
    throw Error("Expected apply failure")
}

WebTest_StartUnicodePreview() {
    WebTest_PrepareUnicode()
    LTWebUnicodeInput.Prewarm()
    LTWebUnicodeInput.Open("clipboard")
}

WebTest_StartPrewarmTimer() {
    SetTimer(WebTest_CheckDelayedPrewarm, -2500)
}

WebTest_CheckDelayedPrewarm() {
    try {
        deadline := A_TickCount + 10000
        while !LTWebUnicodeInput.Ready && A_TickCount < deadline
            Sleep(50)
        WebTest_Assert(LTWebUnicodeInput.Ready, "delayed prewarm reaches ready state")
        WebTest_Assert(IsObject(LTWebUnicodeInput.Window), "delayed prewarm creates the hidden window")
        WebTest_Assert(!DllCall("IsWindowVisible", "ptr", LTWebUnicodeInput.Window.Hwnd), "prewarmed window stays hidden")
        WebTest_Assert(LTWebUnicodeInput.RegisteredShortcuts.Length = 0, "hidden window registers no contextual shortcuts")
        FileAppend("PASS: delayed prewarm callback creates one ready hidden WebView2`n", "*", "UTF-8")
        LTWebUnicodeInput.Dispose()
        ExitApp(0)
    } catch as err {
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
        LTWebUnicodeInput.Dispose()
        ExitApp(1)
    }
}

WebTest_StartUnicodeBrowser() {
    global g_TestUnicodeStayedHiddenBeforeReady
    WebTest_PrepareUnicode()
    LTWebUnicodeInput.Prewarm()
    LTWebUnicodeInput.Open("clipboard")
    g_TestUnicodeStayedHiddenBeforeReady := !DllCall("IsWindowVisible", "ptr", LTWebUnicodeInput.Window.Hwnd)
    SetTimer(WebTest_UnicodeBrowserRun, -100)
}

WebTest_PrepareUnicode() {
    global g_ConfigPath
    IniWrite("Dark", g_ConfigPath, "Appearance", "Theme")
    IniWrite("2014,00AB,0060", g_ConfigPath, "UnicodeInput", "History")
    IniWrite("0060-2014-0060:3,00AB-0020-00AB:2", g_ConfigPath, "UnicodeInput", "PatternStats")
    IniWrite("1", g_ConfigPath, "UnicodeInput", "ConfirmSelectionWithEnter")
    IniWrite("1", g_ConfigPath, "UnicodeInput", "MoveHistoryOnUse")
    IniWrite("Ctrl", g_ConfigPath, "UnicodeInput", "HistoryShortcutModifier")
    IniWrite("Shift", g_ConfigPath, "UnicodeInput", "FavoriteShortcutModifier")
}

WebTest_UnicodeApplyResult(text, mode) {
    global g_TestUnicodeText := text, g_TestUnicodeMode := mode
}

WebTest_UnicodeBrowserRun() {
    global g_TestUnicodeText := "", g_TestUnicodeMode := ""
    global g_TestUnicodeStayedHiddenBeforeReady
    try {
        WebTest_Assert(g_TestUnicodeStayedHiddenBeforeReady, "window stays hidden until the JavaScript handshake")
        core := LTWebUnicodeInput.Core
        corePtr := core.Ptr
        windowHwnd := LTWebUnicodeInput.Window.Hwnd
        WebTest_Assert(IsObject(core), "Unicode WebView2 initialized without fallback")
        deadline := A_TickCount + 10000
        loop {
            ready := core.ExecuteScriptAsync("document.querySelectorAll('.item').length === 5").await2(3000)
            if ready = "true"
                break
            if A_TickCount > deadline
                throw Error("Unicode frontend did not receive the state")
            Sleep(100)
        }
        script := FileRead(A_ScriptDir "\WebUnicode.BrowserTests.js", "UTF-8")
        core.ExecuteScriptAsync(script).await2(3000)
        WebTest_WaitUnicodeBrowserResult(core, "default")
        bounds := LTWebUnicodeInput.Controller.Bounds
        FileAppend("DISPLAY: controllerVisible=" LTWebUnicodeInput.Controller.IsVisible " bounds=" NumGet(bounds, 0, "int") "," NumGet(bounds, 4, "int") "," NumGet(bounds, 8, "int") "," NumGet(bounds, 12, "int") " hostVisible=" DllCall("IsWindowVisible", "ptr", windowHwnd) "`n", "*", "UTF-8")
        WebTest_Assert(LTWebUnicodeInput.Controller.IsVisible, "WebView controller is visible when the host is shown")
        LTWebUnicodeInput.Shortcut("history", 1)
        Sleep(100)
        focused := core.ExecuteScriptAsync("document.querySelector('.item.selected')?.dataset.kind === 'history' && document.querySelector('.item.selected')?.dataset.index === '1'").await2(3000)
        WebTest_Assert(focused = "true", "confirmed shortcut focuses its history item")
        stream := WebView2.CreateFileStream(A_ScriptDir "\unicode-default.png", "w")
        core.CapturePreviewAsync(0, stream).await2(5000)
        stream := 0

        LTWebUnicodeInput.Window.Show("w560 h400")
        Sleep(150)
        core.ExecuteScriptAsync("window.__ltUnicodeTestResult = null; " script).await2(3000)
        WebTest_WaitUnicodeBrowserResult(core, "compact")
        stream := WebView2.CreateFileStream(A_ScriptDir "\unicode-compact.png", "w")
        core.CapturePreviewAsync(0, stream).await2(5000)
        stream := 0

        core.ExecuteScriptAsync("document.querySelector('#code-input').value='2014'; document.querySelector('#apply').click()").await2(3000)
        deadline := A_TickCount + 5000
        while g_TestUnicodeText = "" && A_TickCount < deadline
            Sleep(50)
        WebTest_Assert(g_TestUnicodeText == "—", "Unicode result reaches the existing output engine")
        WebTest_Assert(g_TestUnicodeMode = "clipboard", "clipboard mode preserved")
        WebTest_Assert(IsObject(LTWebUnicodeInput.Window), "prewarmed window survives apply")
        WebTest_Assert(LTWebUnicodeInput.Core.Ptr = corePtr, "WebView2 controller survives apply")
        WebTest_Assert(!DllCall("IsWindowVisible", "ptr", windowHwnd), "window hides after apply")
        WebTest_Assert(!LTWebUnicodeInput.Controller.IsVisible, "WebView hides after apply")
        warmStart := A_TickCount
        LTWebUnicodeInput.Open("insert")
        warmElapsed := A_TickCount - warmStart
        WebTest_Assert(warmElapsed < 500, "warm reopen is immediate: " warmElapsed " ms")
        WebTest_Assert(LTWebUnicodeInput.Core.Ptr = corePtr, "warm reopen reuses the same WebView2 controller")
        WebTest_Assert(LTWebUnicodeInput.Controller.IsVisible, "warm reopen shows the WebView, not only its host")
        core := LTWebUnicodeInput.Core
        deadline := A_TickCount + 10000
        loop {
            actionLabel := core.ExecuteScriptAsync("document.querySelector('#apply')?.textContent || ''").await2(3000)
            if InStr(actionLabel, "Вставить")
                break
            if A_TickCount > deadline
                throw Error("Unicode insert mode did not render")
            Sleep(100)
        }
        WebTest_Assert(LTWebUnicodeInput.State()["mode"] = "insert", "insert mode preserved")
        cleared := core.ExecuteScriptAsync("document.querySelector('#code-input').value === ''").await2(3000)
        WebTest_Assert(cleared = "true", "warm reopen resets the input")
        enabled := core.ExecuteScriptAsync("!document.querySelector('#apply').disabled").await2(3000)
        WebTest_Assert(enabled = "true", "warm reopen restores input controls")
        LTWebUnicodeInput.Dispose()
        FileAppend("PASS: Unicode prewarm, persistent WebView2, " warmElapsed " ms reopen, state, preview, lists, settings and output handoff`n", "*", "UTF-8")
        ExitApp(0)
    } catch as err {
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
        LTWebUnicodeInput.Dispose()
        ExitApp(1)
    }
}

WebTest_WaitUnicodeBrowserResult(core, sizeName) {
    deadline := A_TickCount + 20000
    loop {
        result := core.ExecuteScriptAsync("window.__ltUnicodeTestResult || null").await2(3000)
        if result != "null" {
            result := JSON.parse(result)
            WebTest_Assert(result["ok"], sizeName ": " result["message"])
            return
        }
        if A_TickCount > deadline
            throw Error("Unicode browser tests timed out: " sizeName)
        Sleep(100)
    }
}

WebTest_BrowserRun() {
    try {
        core := LTWebSettings.Core
        WebTest_Assert(IsObject(core), "WebView2 initialized without fallback")
        deadline := A_TickCount + 10000
        loop {
            ready := core.ExecuteScriptAsync("document.querySelector('#version').textContent.includes('Версия')").await2(3000)
            if ready = "true"
                break
            if A_TickCount > deadline
                throw Error("Frontend did not receive the state")
            Sleep(100)
        }
        stream := WebView2.CreateFileStream(A_ScriptDir "\settings-overview.png", "w")
        core.CapturePreviewAsync(0, stream).await2(5000)
        stream := 0
        core.ExecuteScriptAsync(FileRead(A_ScriptDir "\WebSettings.BrowserTests.js", "UTF-8")).await2(3000)
        deadline := A_TickCount + 20000
        loop {
            result := core.ExecuteScriptAsync("window.__ltTestResult || null").await2(3000)
            if result != "null" {
                result := JSON.parse(result)
                WebTest_Assert(result["ok"], result["message"])
                break
            }
            if A_TickCount > deadline
                throw Error("Browser tests timed out")
            Sleep(100)
        }
        stream := WebView2.CreateFileStream(A_ScriptDir "\settings-hotkeys.png", "w")
        core.CapturePreviewAsync(0, stream).await2(5000)
        stream := 0
        LTWebSettings.Window.Show("w720 h480")
        Sleep(150)
        core.ExecuteScriptAsync("window.__ltTestResult = null; " FileRead(A_ScriptDir "\WebSettings.BrowserTests.js", "UTF-8")).await2(3000)
        deadline := A_TickCount + 20000
        loop {
            result := core.ExecuteScriptAsync("window.__ltTestResult || null").await2(3000)
            if result != "null" {
                result := JSON.parse(result)
                WebTest_Assert(result["ok"], "Compact window: " result["message"])
                break
            }
            if A_TickCount > deadline
                throw Error("Compact browser tests timed out")
            Sleep(100)
        }
        stream := WebView2.CreateFileStream(A_ScriptDir "\settings-compact.png", "w")
        core.CapturePreviewAsync(0, stream).await2(5000)
        stream := 0
        FileAppend("PASS: WebView2 bridge, eight pages, form validation, save, discard and unsaved navigation`n", "*", "UTF-8")
        LTWebSettings.Dispose()
        ExitApp(0)
    } catch as err {
        FileAppend(err.Message "`n" err.Stack "`n", "**", "UTF-8")
        LTWebSettings.Dispose()
        ExitApp(1)
    }
}
