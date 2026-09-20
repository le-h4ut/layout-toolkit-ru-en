; Local WebView2 interface for Unicode Input. Conversion and insertion remain in UnicodeInput.ahk.
class LTWebUnicodeInput {
    static Window := 0
    static Controller := 0
    static Core := 0
    static Events := []
    static Busy := false
    static Initializing := false
    static Ready := false
    static OpenRequested := false
    static LastError := ""
    static LoadGeneration := 0
    static Mode := "insert"
    static PrevHwnd := 0
    static RegisteredShortcuts := []
    static TabFallbackHotkeys := []
    static Url := "https://unicode.layout-toolkit.invalid/index.html"

    static Prewarm(*) {
        if this.Window || this.Initializing
            return
        try this.CreateHidden()
        catch as err {
            this.LastError := err.Message
            this.Dispose()
        }
    }

    static Open(mode := "insert") {
        mode := StrLower(Trim(mode)) = "clipboard" ? "clipboard" : "insert"
        activeHwnd := WinExist("A")
        if !this.Window || activeHwnd != this.Window.Hwnd
            this.PrevHwnd := activeHwnd
        this.Mode := mode
        this.OpenRequested := true

        if this.Ready {
            this.ShowReady()
            return
        }
        if this.Initializing
            return

        try this.CreateHidden()
        catch as err {
            this.LastError := err.Message
            this.OpenFallback()
        }
    }

    static CreateHidden() {
        if this.Window || this.Initializing
            return
        this.Initializing := true
        this.LastError := ""
        this.Window := Gui("+AlwaysOnTop +Resize +MinSize560x400", this.Title())
        this.Window.BackColor := LTWebSettings.LoadTheme() = "Dark" ? "101619" : "F5F7FA"
        this.Window.OnEvent("Close", (*) => this.Hide())
        this.Window.OnEvent("Escape", (*) => this.Hide())
        this.Window.OnEvent("Size", (*) => this.Resize())
        LTApplyWindowTheme(this.Window.Hwnd, LTWebSettings.LoadTheme())
        this.Window.Show("Hide w650 h500")

        try {
            assets := A_ScriptDir "\Assets\WebUnicodeInput"
            for name in ["index.html", "unicode.css", "unicode.js"]
                if !FileExist(assets "\" name)
                    throw Error("Не найден файл веб-интерфейса: " assets "\" name)

            profile := EnvGet("LOCALAPPDATA") "\Layout Toolkit\WebView2\UnicodeInput"
            this.Controller := WebView2.CreateControllerAsync(this.Window.Hwnd, 0, profile).await2(15000)
            this.Core := this.Controller.CoreWebView2
            this.Core.SetVirtualHostNameToFolderMapping("unicode.layout-toolkit.invalid", assets, 0)
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
            this.Core.Navigate(this.Url)
            generation := ++this.LoadGeneration
            SetTimer(ObjBindMethod(this, "CheckLoadTimeout", generation), -10000)
        } catch as err {
            this.Dispose()
            throw err
        } finally {
            this.Initializing := false
        }
    }

    static NavigationCompleted(sender, args) {
        if !args.IsSuccess {
            this.LastError := "Не удалось загрузить локальный интерфейс (код " args.WebErrorStatus ")"
            SetTimer((*) => this.HandleLoadFailure(), -1)
            return
        }
        ; NavigationCompleted can also fire for WebView2's initial blank page.
        ; Ready is set only when unicode.js explicitly requests its state.
    }

    static CheckLoadTimeout(generation) {
        if generation != this.LoadGeneration || this.Ready || !this.Window
            return
        this.LastError := "Локальный интерфейс не ответил за 10 секунд"
        this.HandleLoadFailure()
    }

    static HandleLoadFailure() {
        if this.OpenRequested
            this.OpenFallback()
        else
            this.Dispose()
    }

    static ShowReady() {
        if !this.Window || !this.Ready
            return
        this.OpenRequested := false
        this.Window.Title := this.Title()
        this.RefreshTheme()
        this.Window.Show()
        ; A controller created under a hidden HWND stays invisible even after
        ; Gui.Show(). Its visibility is independent of the host window.
        this.Controller.Fill()
        this.Controller.IsVisible := true
        this.Controller.MoveFocus(0)
        this.UnregisterShortcuts()
        this.RegisterShortcuts()
        this.Send(Map("type", "open", "state", this.State()))
    }

    static Hide(*) {
        this.OpenRequested := false
        this.UnregisterShortcuts()
        if this.Controller
            try this.Controller.IsVisible := false
        if this.Window
            try this.Window.Hide()
        this.Send(Map("type", "reset"))
        this.Busy := false
    }

    static OpenFallback() {
        fallbackMode := this.Mode
        errorMessage := this.LastError != "" ? this.LastError : "Не удалось запустить WebView2"
        this.Dispose()
        OpenNativeUnicodeInput(fallbackMode)
        MsgBox("Веб-интерфейс Unicode Input недоступен. Открыто стандартное окно.`n`n" errorMessage, "Layout Toolkit — Unicode Input", "Icon!")
    }

    static Title() => this.Mode = "clipboard" ? "Unicode Input — буфер обмена" : "Unicode Input — вставка"

    static Resize() {
        if this.Controller
            try this.Controller.Fill()
    }

    static Dispose(*) {
        this.UnregisterShortcuts()
        this.Events := []
        if this.Controller
            try this.Controller.Close()
        this.Core := this.Controller := 0
        if this.Window
            try this.Window.Destroy()
        this.Window := 0
        this.Busy := false
        this.Initializing := false
        this.Ready := false
        this.OpenRequested := false
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
            if StrLen(raw) > 65536
                throw Error("Сообщение слишком большое")
            message := JSON.parse(raw)
            if !(message is Map) || !message.Has("command") || !message.Has("id")
                return
            if message["command"] = "state" && !this.Ready {
                this.Ready := true
                if this.OpenRequested
                    SetTimer((*) => this.ShowReady(), -1)
            }
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
                case "preview": result := this.Preview(data)
                case "applyInput": this.ApplyInput(data), result := Map("closed", JSON.true)
                case "applyItem": this.ApplyItem(data), result := Map("closed", JSON.true)
                case "saveSettings": result := this.SaveSettings(data)
                case "close": this.Hide(), result := Map("closed", JSON.true)
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
        UnicodeInput_LoadHistory()
        favorites := [], history := []
        for index, pattern in UnicodeInput_GetAutoFavorites()
            favorites.Push(Map("index", index, "code", pattern, "preview", UnicodeInput_PatternPreview(pattern)))
        for index, hex in UnicodeInput_GetHistory()
            history.Push(Map("index", index, "code", hex, "preview", UnicodeInput_CodePreview(hex)))
        historyModifier := UnicodeInput_LoadHistoryShortcutModifier()
        favoriteModifier := UnicodeInput_LoadFavoriteShortcutModifier()
        UnicodeInput_ResolveShortcutModifiers(&historyModifier, &favoriteModifier)
        return Map(
            "mode", this.Mode,
            "theme", LTWebSettings.LoadTheme(),
            "title", this.Title(),
            "action", this.Mode = "clipboard" ? "Копировать" : "Вставить",
            "description", this.Mode = "clipboard" ? "Результат будет скопирован в буфер обмена" : "Результат будет вставлен в предыдущее окно",
            "favorites", favorites, "history", history,
            "settings", Map(
                "confirm", UnicodeInput_LoadConfirmSelectionWithEnter(),
                "moveHistory", UnicodeInput_LoadMoveHistoryOnUse(),
                "historyModifier", historyModifier,
                "favoriteModifier", favoriteModifier,
                "historyShortcut", UnicodeInput_GetShortcutDisplay(historyModifier),
                "favoriteShortcut", UnicodeInput_GetShortcutDisplay(favoriteModifier)))
    }

    static RefreshTheme() {
        theme := LTWebSettings.LoadTheme()
        if this.Window {
            this.Window.BackColor := theme = "Dark" ? "101619" : "F5F7FA"
            LTApplyWindowTheme(this.Window.Hwnd, theme)
        }
        if this.Core {
            this.Send(Map("type", "theme", "theme", theme))
        }
    }

    static Preview(data) {
        input := Trim(String(data.Get("input", "")))
        if StrLen(input) > 512
            throw Error("Слишком длинная последовательность")
        if input = ""
            return Map("valid", JSON.false, "empty", JSON.true, "preview", "")
        codes := UnicodeInput_ParseCodes(input)
        if !IsObject(codes) || codes.Length = 0
            return Map("valid", JSON.false, "empty", JSON.false, "preview", "")
        preview := UnicodeInput_CodesPreview(codes)
        return Map("valid", preview != "", "empty", JSON.false, "preview", preview, "codes", codes)
    }

    static ApplyInput(data) {
        input := Trim(String(data.Get("input", "")))
        if input = "" || StrLen(input) > 512
            throw Error("Введите Unicode-код в HEX")
        codes := UnicodeInput_ParseCodes(input)
        if !IsObject(codes) || codes.Length = 0
            throw Error("Некорректный Unicode HEX-код")
        text := UnicodeInput_CodesToText(codes)
        if text = ""
            throw Error("Не удалось преобразовать Unicode-код")
        this.ApplyAndClose(text, codes)
    }

    static ApplyItem(data) {
        kind := String(data.Get("kind", ""))
        index := Integer(data.Get("index", 0))
        if index < 1 || index > 5
            throw Error("Элемент быстрого выбора не найден")
        if kind = "history" {
            items := UnicodeInput_GetHistory()
            if index > items.Length
                throw Error("Элемент истории не найден")
            codes := [items[index]]
        } else if kind = "favorite" {
            items := UnicodeInput_GetAutoFavorites()
            if index > items.Length
                throw Error("Элемент избранного не найден")
            codes := UnicodeInput_PatternToCodes(items[index])
        } else {
            throw Error("Неизвестный список быстрого выбора")
        }
        text := UnicodeInput_CodesToText(codes)
        if text = ""
            throw Error("Не удалось преобразовать Unicode-код")
        this.ApplyAndClose(text, codes)
    }

    static SaveSettings(data) {
        changed := String(data.Get("changed", ""))
        confirm := this.Bool(data, "confirm")
        moveHistory := this.Bool(data, "moveHistory")
        historyModifier := UnicodeInput_NormalizeShortcutModifier(String(data.Get("historyModifier", "")), "Ctrl")
        favoriteModifier := UnicodeInput_NormalizeShortcutModifier(String(data.Get("favoriteModifier", "")), "Shift")
        oldHistory := UnicodeInput_LoadHistoryShortcutModifier()
        oldFavorite := UnicodeInput_LoadFavoriteShortcutModifier()

        if historyModifier = favoriteModifier {
            if changed = "historyModifier"
                favoriteModifier := oldHistory
            else if changed = "favoriteModifier"
                historyModifier := oldFavorite
            else
                throw Error("Для истории и избранного нужны разные клавиши")
        }
        if historyModifier = favoriteModifier
            throw Error("Для истории и избранного нужны разные клавиши")

        UnicodeInput_SaveConfirmSelectionWithEnter(confirm)
        UnicodeInput_SaveMoveHistoryOnUse(moveHistory)
        if !UnicodeInput_SaveShortcutModifiers(historyModifier, favoriteModifier)
            throw Error("Не удалось сохранить сочетания быстрого выбора")
        try SettingsGui_UpdateUnicodeControls()
        this.RefreshSettings()
        return this.State()
    }

    static Bool(data, key) {
        if !data.Has(key) || !(data[key] is Integer) || (data[key] != 0 && data[key] != 1)
            throw Error("Некорректное значение: " key)
        return data[key]
    }

    static ApplyAndClose(text, codes) {
        mode := this.Mode
        prevHwnd := this.PrevHwnd
        UnicodeInput_UpdateHistory(codes, UnicodeInput_LoadMoveHistoryOnUse())
        UnicodeInput_UpdatePatternStats(codes)
        this.Hide()
        if mode = "insert" && prevHwnd {
            try {
                if WinExist("ahk_id " prevHwnd) {
                    WinActivate("ahk_id " prevHwnd)
                    Sleep(60)
                }
            }
        }
        UnicodeInput_ApplyResult(text, mode)
    }

    static RefreshSettings() {
        if !this.Window
            return
        this.UnregisterShortcuts()
        this.RegisterShortcuts()
        this.Send(Map("type", "state", "state", this.State()))
    }

    static RegisterShortcuts() {
        if !this.Window
            return
        historyModifier := UnicodeInput_LoadHistoryShortcutModifier()
        favoriteModifier := UnicodeInput_LoadFavoriteShortcutModifier()
        UnicodeInput_ResolveShortcutModifiers(&historyModifier, &favoriteModifier)
        HotIfWinActive("ahk_id " this.Window.Hwnd)
        Loop 5 {
            historyHotkey := UnicodeInput_GetShortcutHotkey(historyModifier, A_Index)
            favoriteHotkey := UnicodeInput_GetShortcutHotkey(favoriteModifier, A_Index)
            Hotkey(historyHotkey, ObjBindMethod(this, "Shortcut", "history", A_Index), "On")
            Hotkey(favoriteHotkey, ObjBindMethod(this, "Shortcut", "favorite", A_Index), "On")
            this.RegisteredShortcuts.Push(historyHotkey)
            this.RegisteredShortcuts.Push(favoriteHotkey)
        }
        if historyModifier != "Tab" && favoriteModifier != "Tab" {
            this.TabFallbackHotkeys := ["$Tab", "$+Tab"]
            Hotkey(this.TabFallbackHotkeys[1], (*) => Send("{Tab}"), "On")
            Hotkey(this.TabFallbackHotkeys[2], (*) => Send("+{Tab}"), "On")
        }
        HotIf()
    }

    static UnregisterShortcuts() {
        if !this.Window
            return
        HotIfWinActive("ahk_id " this.Window.Hwnd)
        for hotkeyName in this.RegisteredShortcuts
            try Hotkey(hotkeyName, "Off")
        for hotkeyName in this.TabFallbackHotkeys
            try Hotkey(hotkeyName, "Off")
        HotIf()
        this.RegisteredShortcuts := []
        this.TabFallbackHotkeys := []
    }

    static Shortcut(kind, index, *) {
        items := kind = "history" ? UnicodeInput_GetHistory() : UnicodeInput_GetAutoFavorites()
        if index > items.Length {
            SoundBeep(750, 120)
            return
        }
        if UnicodeInput_LoadConfirmSelectionWithEnter() {
            this.Send(Map("type", "focus", "kind", kind, "index", index))
            return
        }
        try this.ApplyItem(Map("kind", kind, "index", index))
    }
}

UnicodeInput(mode := "insert") {
    LTWebUnicodeInput.Open(mode)
}
