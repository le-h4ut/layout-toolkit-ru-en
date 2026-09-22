; Compact first-run guide. The native guide remains available if WebView2 fails.
class LTWebWelcome {
    static Window := 0
    static Controller := 0
    static Core := 0
    static Events := []
    static Ready := false
    static Requested := false
    static FirstRun := false
    static Generation := 0
    static LastError := ""
    static Url := "https://welcome.layout-toolkit.invalid/index.html"

    static Open(isFirstRun := false) {
        this.FirstRun := isFirstRun
        this.Requested := true
        if this.Ready {
            this.ShowReady()
            return
        }
        if this.Window
            return
        try this.CreateHidden()
        catch as err {
            this.LastError := err.Message
            this.OpenFallback()
        }
    }

    static CreateHidden() {
        theme := LTWebSettings.LoadTheme()
        this.Window := Gui("+AlwaysOnTop +Resize +MinSize650x440", "Layout Toolkit — краткая справка")
        this.Window.BackColor := theme = "Dark" ? "101619" : "F5F7FA"
        this.Window.OnEvent("Close", (*) => this.Hide())
        this.Window.OnEvent("Escape", (*) => this.Hide())
        this.Window.OnEvent("Size", (*) => this.Resize())
        LTApplyWindowTheme(this.Window.Hwnd, theme)
        this.Window.Show("Hide w700 h460")

        assets := A_ScriptDir "\Assets\WebWelcome"
        for name in ["index.html", "welcome.css", "welcome.js"]
            if !FileExist(assets "\" name)
                throw Error("Не найден файл приветственного окна: " name)
        profile := EnvGet("LOCALAPPDATA") "\Layout Toolkit\WebView2\Welcome"
        this.Controller := WebView2.CreateControllerAsync(this.Window.Hwnd, 0, profile).await2(15000)
        this.Core := this.Controller.CoreWebView2
        this.Core.SetVirtualHostNameToFolderMapping("welcome.layout-toolkit.invalid", assets, 0)
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
        generation := ++this.Generation
        SetTimer(ObjBindMethod(this, "CheckTimeout", generation), -10000)
    }

    static NavigationCompleted(sender, args) {
        if !args.IsSuccess {
            this.LastError := "Не удалось загрузить страницу: " args.WebErrorStatus
            SetTimer((*) => this.OpenFallback(), -1)
        }
    }

    static CheckTimeout(generation) {
        if generation = this.Generation && this.Window && !this.Ready {
            this.LastError := "Страница не ответила за 10 секунд"
            this.OpenFallback()
        }
    }

    static Receive(sender, args) {
        if args.Source != this.Url
            return
        try {
            message := JSON.parse(args.WebMessageAsJson)
            if !(message is Map) || !message.Has("command")
                return
            SetTimer((*) => this.Dispatch(message), -1)
        }
    }

    static Dispatch(message) {
        switch message["command"] {
            case "ready":
                this.Ready := true
                if this.Requested
                    this.ShowReady()
            case "save":
                if !this.Window
                    return
                global g_ConfigPath, g_LiveEnabled, g_AppName
                desiredLive := message.Get("live", false) = true
                IniWrite("1", g_ConfigPath, "General", "FirstRunDone")
                SetLiveMode(desiredLive, false, false)
                this.Hide(false)
                Notify("Готово. Live: " (g_LiveEnabled ? "включён" : "выключен"), g_AppName, "Iconi")
            case "settings":
                OpenSettingsGui()
            case "close":
                this.Hide()
        }
    }

    static State() {
        global g_LiveEnabled, g_HotkeyLayoutFull, g_HotkeyLayoutMajority
        global g_HotkeyLiveToggle, g_HotkeyLiveConvert, g_HotkeyUnicodeInput
        global g_HotkeyCapsLockFix, g_HotkeyCapsLockFullFix
        return Map(
            "theme", LTWebSettings.LoadTheme(), "firstRun", this.FirstRun,
            "live", g_LiveEnabled ? JSON.true : JSON.false,
            "layoutFull", HotkeyToDisplay(g_HotkeyLayoutFull),
            "layoutMajority", HotkeyToDisplay(g_HotkeyLayoutMajority),
            "liveToggle", HotkeyToDisplay(g_HotkeyLiveToggle),
            "liveConvert", HotkeyToDisplay(g_HotkeyLiveConvert),
            "unicode", HotkeyToDisplay(g_HotkeyUnicodeInput),
            "capsFull", HotkeyToDisplay(g_HotkeyCapsLockFullFix),
            "capsSmart", HotkeyToDisplay(g_HotkeyCapsLockFix)
        )
    }

    static ShowReady() {
        if !this.Window || !this.Ready || !this.Requested
            return
        theme := LTWebSettings.LoadTheme()
        this.Window.BackColor := theme = "Dark" ? "101619" : "F5F7FA"
        LTApplyWindowTheme(this.Window.Hwnd, theme)
        this.Window.Show()
        this.Controller.Fill()
        this.Controller.IsVisible := true
        this.Controller.MoveFocus(0)
        this.Core.PostWebMessageAsJson(JSON.stringify(Map("type", "state", "state", this.State())))
    }

    static Hide(keepFirstRunPending := true) {
        global g_ConfigPath
        if keepFirstRunPending && this.FirstRun
            IniWrite("0", g_ConfigPath, "General", "FirstRunDone")
        this.Requested := false
        this.FirstRun := false
        if this.Controller
            try this.Controller.IsVisible := false
        if this.Window
            this.Window.Hide()
    }

    static Resize() {
        if this.Controller
            try this.Controller.Fill()
    }

    static OpenFallback() {
        if !this.Requested {
            this.Dispose()
            return
        }
        isFirstRun := this.FirstRun
        this.Dispose()
        ShowNativeTrainingGui(isFirstRun)
    }

    static Dispose() {
        this.Generation += 1
        this.Events := []
        if this.Controller
            try this.Controller.Close()
        this.Core := this.Controller := 0
        if this.Window
            try this.Window.Destroy()
        this.Window := 0
        this.Ready := false
        this.Requested := false
    }
}
