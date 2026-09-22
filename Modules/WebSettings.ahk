; Local HTML settings, hosted by WebView2. No HTTP server or remote UI.
#Include Vendor\JSON.ahk
#Include Vendor\WebView2\WebView2.ahk

; Keep the native frame in sync with the WebView theme. Attribute 20 is the
; current DWMWA_USE_IMMERSIVE_DARK_MODE value; early Windows 10 builds use 19.
LTRefreshWindowFrame(hwnd) {
    if !DllCall("IsWindowVisible", "Ptr", hwnd, "Int") || DllCall("IsIconic", "Ptr", hwnd, "Int")
        return

    ; Windows 10 may retain the old caption until a real size/state change.
    ; Suppress intermediate painting, trigger that change, then redraw once.
    DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x0B, "Ptr", 0, "Ptr", 0, "Ptr")
    try {
        if DllCall("IsZoomed", "Ptr", hwnd, "Int") {
            DllCall("ShowWindow", "Ptr", hwnd, "Int", 9, "Int")
            DllCall("ShowWindow", "Ptr", hwnd, "Int", 3, "Int")
        } else {
            rect := Buffer(16, 0)
            if DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect, "Int") {
                width := NumGet(rect, 8, "Int") - NumGet(rect, 0, "Int")
                height := NumGet(rect, 12, "Int") - NumGet(rect, 4, "Int")
                if width > 1 {
                    flags := 0x16 ; SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE
                    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", width - 1, "Int", height, "UInt", flags, "Int")
                    DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", width, "Int", height, "UInt", flags, "Int")
                }
            }
        }
    } finally {
        DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x0B, "Ptr", 1, "Ptr", 0, "Ptr")
        DllCall("RedrawWindow", "Ptr", hwnd, "Ptr", 0, "Ptr", 0, "UInt", 0x581, "Int")
    }
}

LTApplyWindowTheme(hwnd, theme) {
    if !hwnd || !DllCall("IsWindow", "Ptr", hwnd, "Int")
        return false
    enabled := StrLower(Trim(String(theme))) = "dark" ? 1 : 0
    try {
        attribute := 20
        result := DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 20, "Int*", enabled, "UInt", 4, "Int")
        if result != 0 {
            attribute := 19
            result := DllCall("dwmapi\DwmSetWindowAttribute", "Ptr", hwnd, "UInt", 19, "Int*", enabled, "UInt", 4, "Int")
        }
        if result != 0
            return false
        ; Recalculate the non-client frame without recreating HWND.
        DllCall("SetWindowPos", "Ptr", hwnd, "Ptr", 0, "Int", 0, "Int", 0, "Int", 0, "Int", 0, "UInt", 0x37, "Int")
        ; Try the cheap activation refresh first, then force a real state/size
        ; change for Windows 10 builds that keep the old caption cached.
        active := DllCall("GetForegroundWindow", "Ptr") = hwnd ? 1 : 0
        DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x86, "Ptr", !active, "Ptr", 0, "Ptr")
        DllCall("SendMessage", "Ptr", hwnd, "UInt", 0x86, "Ptr", active, "Ptr", 0, "Ptr")
        LTRefreshWindowFrame(hwnd)
        return attribute
    } catch {
        return false
    }
}

class LTWebSettings {
    static Window := 0
    static Controller := 0
    static Core := 0
    static Events := []
    static Busy := false
    static Capture := 0
    static CaptureFocusTimer := 0
    static LoadingWindow := 0
    static Initializing := false
    static Requested := false
    static Ready := false
    static LoadGeneration := 0
    static Url := "https://layout-toolkit.invalid/index.html"

    static Open() {
        this.Requested := true
        if this.Ready {
            this.ShowReady()
            return
        }
        if this.Window || this.Initializing {
            if this.LoadingWindow
                this.LoadingWindow.Show()
            return
        }
        this.ShowLoading()
        this.Initializing := true
        try this.CreateHidden()
        catch as err {
            this.OpenFallback(err.Message)
        } finally {
            this.Initializing := false
        }
    }

    static ShowLoading() {
        if this.LoadingWindow
            return
        theme := this.LoadTheme()
        this.LoadingWindow := Gui("+AlwaysOnTop -Resize -MinimizeBox -MaximizeBox", "Layout Toolkit")
        this.LoadingWindow.BackColor := theme = "Dark" ? "101619" : "F5F7FA"
        this.LoadingWindow.SetFont("s10 " (theme = "Dark" ? "cE6EDEF" : "c203035"), "Segoe UI")
        this.LoadingWindow.AddText("x20 y22 w240 h25", "Загрузка настроек…")
        this.LoadingWindow.OnEvent("Close", (*) => this.CancelLoading())
        LTApplyWindowTheme(this.LoadingWindow.Hwnd, theme)
        this.LoadingWindow.Show("w280 h72")
    }

    static CancelLoading() {
        this.Requested := false
        if this.LoadingWindow
            this.LoadingWindow.Hide()
        if !this.Initializing
            this.Dispose()
    }

    static CreateHidden() {
        this.Window := Gui("+Resize +MinSize720x480", "Layout Toolkit — Настройки")
        this.Window.BackColor := this.LoadTheme() = "Dark" ? "101619" : "F5F7FA"
        this.Window.OnEvent("Close", (*) => this.Dispose())
        this.Window.OnEvent("Size", (*) => this.Resize())
        LTApplyWindowTheme(this.Window.Hwnd, this.LoadTheme())
        this.Window.Show("Hide w800 h540")
        assets := A_ScriptDir "\Assets\WebSettings"
        for name in ["index.html", "settings.css", "settings.js"]
            if !FileExist(assets "\" name)
                throw Error("Не найден файл веб-интерфейса: " assets "\" name)
        profile := EnvGet("LOCALAPPDATA") "\Layout Toolkit\WebView2"
        this.Controller := WebView2.CreateControllerAsync(this.Window.Hwnd, 0, profile).await2(15000)
        if !this.Requested {
            this.Dispose()
            return
        }
        this.Core := this.Controller.CoreWebView2
        this.Core.SetVirtualHostNameToFolderMapping("layout-toolkit.invalid", assets, 0)
        settings := this.Core.Settings
        settings.AreHostObjectsAllowed := false
        settings.AreDefaultContextMenusEnabled := false
        settings.AreDevToolsEnabled := false
        settings.IsStatusBarEnabled := false
        settings.AreBrowserAcceleratorKeysEnabled := false
        settings.AreDefaultScriptDialogsEnabled := false
        try this.Core.Profile.PreferredColorScheme := 1
        this.Events := [
            this.Core.WebMessageReceived(ObjBindMethod(this, "Receive")),
            this.Core.NavigationStarting((sender, args) => args.Cancel := !(args.Uri == this.Url)),
            this.Core.NavigationCompleted(ObjBindMethod(this, "NavigationCompleted")),
            this.Core.NewWindowRequested((sender, args) => args.Handled := true),
            this.Core.PermissionRequested((sender, args) => args.State := 2)
        ]
        generation := ++this.LoadGeneration
        this.Core.Navigate(this.Url)
        SetTimer(ObjBindMethod(this, "CheckLoadTimeout", generation), -10000)
    }

    static NavigationCompleted(sender, args) {
        if !args.IsSuccess {
            reason := "Не удалось загрузить интерфейс (код " args.WebErrorStatus ")"
            generation := this.LoadGeneration
            SetTimer((*) => this.OpenFallback(reason, generation), -1)
        }
    }

    static CheckLoadTimeout(generation) {
        if generation = this.LoadGeneration && this.Window && !this.Ready
            this.OpenFallback("Интерфейс не ответил за 10 секунд", generation)
    }

    static ShowReady() {
        if !this.Requested || !this.Ready || !this.Window || !this.Controller
            return
        theme := this.LoadTheme()
        this.Window.BackColor := theme = "Dark" ? "101619" : "F5F7FA"
        LTApplyWindowTheme(this.Window.Hwnd, theme)
        this.Window.Show()
        this.Controller.Fill()
        this.Controller.IsVisible := true
        this.Controller.MoveFocus(0)
        this.Send(Map("type", "state", "state", this.State()))
        this.CloseLoading()
    }

    static CloseLoading() {
        window := this.LoadingWindow
        this.LoadingWindow := 0
        if window
            try window.Destroy()
    }

    static OpenFallback(reason, generation := 0) {
        if generation && generation != this.LoadGeneration
            return
        if !this.Requested {
            this.Dispose()
            return
        }
        this.Dispose()
        OpenNativeSettingsGui()
        MsgBox("Веб-настройки недоступны. Открыто стандартное окно.`n`nДля веб-интерфейса нужен Microsoft Edge WebView2 Runtime.`n`n" reason, "Layout Toolkit", "Icon!")
    }

    static Resize() {
        if this.Controller
            try this.Controller.Fill()
    }

    static Hide() {
        this.Dispose()
    }

    static Dispose(*) {
        this.Requested := false
        this.Ready := false
        this.LoadGeneration += 1
        if this.CaptureFocusTimer
            SetTimer(this.CaptureFocusTimer, 0)
        this.CaptureFocusTimer := 0
        if this.Capture
            this.Capture.Stop()
        this.Capture := 0
        this.Busy := false
        this.Events := []
        if this.Controller
            try this.Controller.Close()
        this.Core := this.Controller := 0
        if this.Window
            try this.Window.Destroy()
        this.Window := 0
        this.CloseLoading()
    }

    static Send(message) {
        if this.Core
            try this.Core.PostWebMessageAsJson(JSON.stringify(message))
    }

    static Receive(sender, args) {
        if !(args.Source == this.Url)
            return
        try {
            raw := args.WebMessageAsJson
            if StrLen(raw) > 262144
                throw Error("Сообщение слишком большое")
            message := JSON.parse(raw)
            if !(message is Map) || !message.Has("command")
                return
            if message["command"] = "uiReady" {
                this.Ready := true
                SetTimer((*) => this.ShowReady(), -1)
                return
            }
            if !message.Has("id")
                return
            ; Leave the COM event before starting InputHook or showing a dialog.
            SetTimer((*) => this.Dispatch(message), -1)
        } catch as err {
            this.Send(Map("type", "error", "message", err.Message))
        }
    }

    static Dispatch(message) {
        if this.Busy {
            this.Send(Map("id", message["id"], "ok", JSON.false, "error", "Дождитесь завершения предыдущей команды"))
            return
        }
        this.Busy := true
        try {
            data := message.Get("data", Map())
            switch message["command"] {
                case "state": result := this.State()
                case "saveTheme": result := this.SaveTheme(data)
                case "saveLive": this.SaveLive(data), result := this.State()
                case "saveUnicode": this.SaveUnicode(data), result := this.State()
                case "saveHotkeys": this.SaveHotkeys(data), result := this.State()
                case "capture": result := this.CaptureHotkey(data["action"])
                case "action": this.Action(data["name"]), result := this.State()
                default: throw Error("Неизвестная команда")
            }
            this.Send(Map("id", message["id"], "ok", JSON.true, "result", result))
        } catch as err {
            this.Send(Map("id", message["id"], "ok", JSON.false, "error", err.Message))
        } finally {
            this.Busy := false
        }
    }

    static State() {
        global g_ConfigDir, g_LiveEnabled, g_LiveTriggerMode, g_DoubleSpaceMs, g_LiveSwitchInputLanguage, g_ShowFirstToggleHint
        global g_ShowTrayTips, g_PlaySound, g_ExcludeWords, g_ExcludePath
        hotkeys := []
        values := SettingsGui_GetCurrentHotkeyValues()
        ; Map enumeration sorts keys; preserve the original native GUI order.
        for action in ["LayoutFull", "LayoutMajority", "LiveToggle", "LiveConvert", "UnicodeInput", "CapsLockFix", "CapsLockFullFix"] {
            value := values[action]
            hotkeys.Push(Map("action", action, "label", SettingsGui_GetHotkeyLabel(action), "value", value, "display", HotkeyToDisplay(value)))
        }
        return Map(
            "version", SettingsGui_GetVersionFromChangelog(), "dataDir", g_ConfigDir, "theme", this.LoadTheme(),
            "live", Map("enabled", g_LiveEnabled, "trigger", g_LiveTriggerMode, "interval", g_DoubleSpaceMs, "switchInputLanguage", g_LiveSwitchInputLanguage, "hint", g_ShowFirstToggleHint),
            "notifications", g_ShowTrayTips, "sound", g_PlaySound, "hotkeys", hotkeys,
            "unicode", Map("confirm", UnicodeInput_LoadConfirmSelectionWithEnter(), "moveHistory", UnicodeInput_LoadMoveHistoryOnUse(), "history", UnicodeInput_LoadHistoryShortcutModifier(), "favorite", UnicodeInput_LoadFavoriteShortcutModifier()),
            "excludeCount", g_ExcludeWords.Count, "excludePath", g_ExcludePath)
    }

    static LoadTheme() {
        global g_ConfigPath
        return StrLower(Trim(IniRead(g_ConfigPath, "Appearance", "Theme", "Light"))) = "dark" ? "Dark" : "Light"
    }

    static SaveTheme(data) {
        global g_ConfigPath
        theme := StrLower(Trim(String(data.Get("theme", ""))))
        if theme != "light" && theme != "dark"
            throw Error("Неизвестная тема")
        theme := theme = "dark" ? "Dark" : "Light"
        IniWrite(theme, g_ConfigPath, "Appearance", "Theme")
        if this.Window {
            this.Window.BackColor := theme = "Dark" ? "101619" : "F5F7FA"
            LTApplyWindowTheme(this.Window.Hwnd, theme)
        }
        try LTWebUnicodeInput.RefreshTheme()
        return Map("theme", theme)
    }

    static Bool(data, key) {
        if !data.Has(key) || !(data[key] is Integer) || (data[key] != 0 && data[key] != 1)
            throw Error("Некорректное значение: " key)
        return data[key]
    }

    ; Keep the previous file if a write or runtime update fails.
    static WriteIni(path, entries, apply, rollback) {
        backup := path ".web-backup-" A_TickCount
        existed := FileExist(path)
        if existed
            FileCopy(path, backup, false)
        try {
            for item in entries
                IniWrite(item[3], path, item[1], item[2])
            apply.Call()
        } catch as err {
            if existed
                FileCopy(backup, path, true)
            else if FileExist(path)
                FileDelete(path)
            rollback.Call()
            throw err
        } finally {
            if FileExist(backup)
                FileDelete(backup)
        }
    }

    static SaveLive(data) {
        global g_ConfigPath, g_LiveBusy
        if g_LiveBusy
            throw Error("Дождитесь завершения Live-исправления")
        trigger := data["trigger"]
        if (trigger != "DoubleSpace" && trigger != "Hotkey")
            throw Error("Неизвестный способ запуска")
        interval := NormalizeLiveDoubleSpaceMs(String(data["interval"]), "")
        if (interval == "")
            throw Error("Интервал должен быть целым числом от 100 до 3000 мс")
        entries := [["General", "LiveEnabled", this.Bool(data, "enabled")], ["General", "LiveTriggerMode", trigger], ["General", "DoubleSpaceMs", interval], ["General", "LiveSwitchInputLanguage", this.Bool(data, "switchInputLanguage")], ["General", "ShowFirstToggleHint", this.Bool(data, "hint")]]
        this.WriteIni(g_ConfigPath, entries, ObjBindMethod(this, "ApplyLive"), ObjBindMethod(this, "ApplyLive"))
    }

    static ApplyLive() {
        global g_ConfigPath, g_LiveTriggerMode, g_DoubleSpaceMs, g_LiveSwitchInputLanguage, g_ShowFirstToggleHint
        g_LiveTriggerMode := ReadLiveTriggerMode()
        g_DoubleSpaceMs := ReadLiveDoubleSpaceMs()
        g_LiveSwitchInputLanguage := IniRead(g_ConfigPath, "General", "LiveSwitchInputLanguage", "0") = "1"
        g_ShowFirstToggleHint := IniRead(g_ConfigPath, "General", "ShowFirstToggleHint", "1") = "1"
        if !SetLiveMode(IniRead(g_ConfigPath, "General", "LiveEnabled", "0") = "1", false, false)
            throw Error("Не удалось применить Live-настройки. Проверьте конфликты горячих клавиш.")
    }

    static SaveUnicode(data) {
        global g_ConfigPath
        choices := "|Ctrl|Shift|Alt|Win|Tab|"
        history := data["history"], favorite := data["favorite"]
        if !InStr(choices, "|" history "|", true) || !InStr(choices, "|" favorite "|", true) || history = favorite
            throw Error("Выберите разные клавиши для истории и избранного")
        entries := [["UnicodeInput", "ConfirmSelectionWithEnter", this.Bool(data, "confirm")], ["UnicodeInput", "MoveHistoryOnUse", this.Bool(data, "moveHistory")], ["UnicodeInput", "HistoryShortcutModifier", history], ["UnicodeInput", "FavoriteShortcutModifier", favorite]]
        this.WriteIni(g_ConfigPath, entries, UnicodeInput_RefreshOpenGuiSettings, UnicodeInput_RefreshOpenGuiSettings)
    }

    static SaveHotkeys(data) {
        global g_HotkeysPath, g_LiveBusy
        if g_LiveBusy
            throw Error("Дождитесь завершения Live-исправления")
        current := SettingsGui_GetCurrentHotkeyValues(), seen := Map(), entries := []
        for action, previous in current {
            value := Trim(data[action])
            ; Preserve hand-edited chords. Hotkey() performs final validation.
            if value == ""
                throw Error("Не задано сочетание: " SettingsGui_GetHotkeyLabel(action))
            if !(value == previous) && (StrLen(value) > 80 || RegExMatch(value, "[\r\n]") || SettingsGui_IsUnsafeBareHotkey(value))
                throw Error("Недопустимое сочетание: " action)
            normalized := SettingsGui_NormalizeHotkeyForCompare(value)
            if seen.Has(normalized)
                throw Error("Одно сочетание назначено двум функциям: " HotkeyToDisplay(value))
            seen[normalized] := true
            entries.Push(["Hotkeys", action, value])
        }
        this.WriteIni(g_HotkeysPath, entries, ObjBindMethod(this, "ApplyHotkeys"), ObjBindMethod(this, "ApplyHotkeys"))
    }

    static ApplyHotkeys() {
        LoadHotkeys()
        if !RegisterHotkeys()
            throw Error("Не удалось зарегистрировать сочетание")
        SetupTrayMenu()
    }

    static CaptureHotkey(action) {
        global g_HotkeyCaptureActive, g_HotkeyCaptureModifiers, g_LiveBusy
        if !SettingsGui_GetCurrentHotkeyValues().Has(action) || g_LiveBusy || g_HotkeyCaptureActive
            throw Error("Сейчас нельзя начать захват сочетания")
        wasSuspended := A_IsSuspended
        try {
            g_HotkeyCaptureActive := true
            g_HotkeyCaptureModifiers := Map("Win", false, "Ctrl", false, "Alt", false, "Shift", false)
            ResetTypingBuffer()
            Suspend(true)
            hook := this.Capture := InputHook("L0 T10")
            hook.KeyOpt("{All}", "ESN")
            hook.KeyOpt("{LControl}{RControl}{LShift}{RShift}{LAlt}{RAlt}{LWin}{RWin}", "-E")
            hook.OnKeyDown := SettingsGui_CaptureKeyDown
            hook.OnKeyUp := SettingsGui_CaptureKeyUp
            hook.Start()
            this.CaptureFocusTimer := (*) => this.CancelCaptureIfInactive()
            SetTimer(this.CaptureFocusTimer, 100)
            hook.Wait()
            key := hook.EndKey
            if key = "" || key = "Escape" || key = "Esc"
                return Map("cancelled", JSON.true)
            value := ""
            for modifier, symbol in Map("Win", "#", "Ctrl", "^", "Alt", "!", "Shift", "+")
                if g_HotkeyCaptureModifiers[modifier]
                    value .= symbol
            value .= StrLen(key) = 1 ? StrLower(key) : key
            if SettingsGui_IsUnsafeBareHotkey(value)
                throw Error("Добавьте Ctrl, Alt, Shift или Win к этой клавише")
            return Map("value", value, "display", HotkeyToDisplay(value))
        } finally {
            if this.CaptureFocusTimer
                SetTimer(this.CaptureFocusTimer, 0)
            this.CaptureFocusTimer := 0
            if this.Capture
                this.Capture.Stop()
            this.Capture := 0
            Suspend(wasSuspended)
            g_HotkeyCaptureActive := false
            ResetTypingBuffer()
        }
    }

    static CancelCaptureIfInactive() {
        if this.Capture && (!this.Window || !WinActive("ahk_id " this.Window.Hwnd))
            this.Capture.Stop()
    }

    static Action(name) {
        switch name {
            case "openData": OpenUserDataDir()
            case "restart": SettingsGui_RestartToolkit()
            case "openHotkeys": OpenHotkeysFile()
            case "reloadHotkeys": this.ApplyHotkeys()
            case "resetHotkeys": RestoreDefaultHotkeys()
            case "unicode": UnicodeInput("clipboard")
            case "openExclude": OpenExcludeFile()
            case "reloadExclude": LoadExcludeWords()
            case "resetExclude": RestoreDefaultExcludeWords()
            default: throw Error("Неизвестное действие")
        }
    }
}

OpenSettingsGui(*) {
    LTWebSettings.Open()
}
