; UnicodeInput.ahk
; Модуль ввода Unicode-символов по HEX-коду.
;
; Поддерживает:
;   AB              -> «
;   фи              -> «
;   60              -> `
;   2014            -> —
;   0060 2014 0060 -> `—`
;   006020140060   -> `—`
;   0060 0020 2014 0020 0060 -> ` — `
;
; История:
;   хранится в settings.ini / [UnicodeInput] / History
;   максимум 5 одиночных HEX-кодов
;   по умолчанию Ctrl+1..5 выбирает или сразу применяет пункт истории
;   MoveHistoryOnUse=1 -> использованные коды поднимаются наверх
;   MoveHistoryOnUse=0 -> существующие коды остаются на местах, наверх добавляются только новые
;
; Избранное:
;   строится автоматически по статистике паттернов из 2+ кодов
;   по умолчанию Shift+1..5 выбирает или сразу применяет пункт избранного
;   одиночные символы в избранное не попадают

g_UnicodeInputHistory := []
g_UnicodeInputGuiStates := Map()


OpenNativeUnicodeInput(mode := "insert") {
    global g_UnicodeInputGuiStates

    mode := StrLower(Trim(mode))

    if (mode != "clipboard") {
        mode := "insert"
    }

    UnicodeInput_LoadHistory()
    moveHistoryOnUse := UnicodeInput_LoadMoveHistoryOnUse()
    confirmSelectionWithEnter := UnicodeInput_LoadConfirmSelectionWithEnter()
    historyModifier := UnicodeInput_LoadHistoryShortcutModifier()
    favoriteModifier := UnicodeInput_LoadFavoriteShortcutModifier()
    UnicodeInput_ResolveShortcutModifiers(&historyModifier, &favoriteModifier)
    favorites := UnicodeInput_GetAutoFavorites()

    prevHwnd := WinExist("A")

    actionText := (mode = "clipboard")
        ? "Будет скопировано в буфер обмена."
        : "Будет вставлено в активное окно."

    title := (mode = "clipboard")
        ? "Unicode Input — буфер обмена"
        : "Unicode Input — вставка"

    guiObj := Gui("+AlwaysOnTop", title)
    guiObj.SetFont("s9 norm", "Segoe UI")

    guiObj.AddText("x20 y16 w540 h22", "Введите Unicode-код в HEX.")
    guiObj.AddText("x20 y38 w540 h22", actionText)

    inputEdit := guiObj.AddEdit("x20 y68 w300 h24 vUnicodeInputCode")
    previewText := guiObj.AddText("x330 y68 w90 h24 Border Center +0x200", "")
    applyText := (mode = "clipboard") ? "Копировать" : "Вставить"
    btnApply := guiObj.AddButton("Default x430 y67 w130 h26", applyText)

    y := 108

    guiObj.SetFont("s9 bold", "Segoe UI")
    favoriteHeader := guiObj.AddText(
        "x20 y" y " w540 h20",
        "Избранное — быстрый выбор: " UnicodeInput_GetShortcutDisplay(favoriteModifier)
    )
    guiObj.SetFont("s9 norm", "Segoe UI")
    y += 26

    favoriteButtons := []

    if (favorites.Length = 0) {
        guiObj.AddText("x20 y" y " w540 h24 Disabled", "Часто используемые последовательности появятся здесь автоматически.")
        y += 32
    } else {
        maxFavItems := Min(favorites.Length, 5)

        Loop maxFavItems {
            index := A_Index
            pattern := favorites[index]
            preview := UnicodeInput_PatternPreview(pattern)
            label := index ". " pattern "    " preview

            btn := guiObj.AddButton("x20 y" y " w540 h28", label)
            btn.OnEvent("Click", UnicodeInput_ApplyFavorite.Bind(guiObj, index))

            favoriteButtons.Push(btn)
            y += 32
        }
    }

    y += 4

    guiObj.SetFont("s9 bold", "Segoe UI")
    historyHeader := guiObj.AddText(
        "x20 y" y " w540 h20",
        "Недавние символы — быстрый выбор: " UnicodeInput_GetShortcutDisplay(historyModifier)
    )
    guiObj.SetFont("s9 norm", "Segoe UI")
    y += 26

    historyButtons := []
    history := UnicodeInput_GetHistory()

    if (history.Length = 0) {
        guiObj.AddText("x20 y" y " w540 h24 Disabled", "История пока пустая.")
        y += 32
    } else {
        maxHistoryItems := Min(history.Length, 5)

        Loop maxHistoryItems {
            index := A_Index
            hex := history[index]
            preview := UnicodeInput_CodePreview(hex)
            label := index ". " hex "    " preview

            btn := guiObj.AddButton("x20 y" y " w540 h28", label)
            btn.OnEvent("Click", UnicodeInput_ApplyHistory.Bind(guiObj, index))

            historyButtons.Push(btn)
            y += 32
        }
    }

    y += 8

    confirmSelectionChk := guiObj.AddCheckbox("x20 y" y " w400 h24", "Подтверждать быстрый выбор клавишей Enter")
    confirmSelectionChk.Value := confirmSelectionWithEnter ? 1 : 0
    y += 28

    moveHistoryChk := guiObj.AddCheckbox("x20 y" y " w400 h24", "Поднимать использованный символ в начало истории")
    moveHistoryChk.Value := moveHistoryOnUse ? 1 : 0
    y += 32

    guiObj.AddText("x20 y" (y + 4) " w205 h24", "Быстрый выбор истории:")
    historyModifierDDL := guiObj.AddDropDownList("x225 y" y " w105 Choose" UnicodeInput_GetModifierIndex(historyModifier), UnicodeInput_GetModifierChoices())
    guiObj.AddText("x338 y" (y + 4) " w80 h24", "+ 1…5")
    y += 32

    guiObj.AddText("x20 y" (y + 4) " w205 h24", "Быстрый выбор избранного:")
    favoriteModifierDDL := guiObj.AddDropDownList("x225 y" y " w105 Choose" UnicodeInput_GetModifierIndex(favoriteModifier), UnicodeInput_GetModifierChoices())
    guiObj.AddText("x338 y" (y + 4) " w80 h24", "+ 1…5")

    btnCancel := guiObj.AddButton("x430 y" (y - 2) " w130 h28", "Отмена")
    windowHeight := y + 52

    state := {
        Gui: guiObj,
        Mode: mode,
        PrevHwnd: prevHwnd,
        Edit: inputEdit,
        PreviewText: previewText,
        FavoriteHeader: favoriteHeader,
        HistoryHeader: historyHeader,
        Favorites: favorites,
        FavoriteButtons: favoriteButtons,
        History: history,
        HistoryButtons: historyButtons,
        ApplyButton: btnApply,
        ConfirmSelectionChk: confirmSelectionChk,
        MoveHistoryChk: moveHistoryChk,
        HistoryModifierDDL: historyModifierDDL,
        FavoriteModifierDDL: favoriteModifierDDL,
        HistoryModifier: historyModifier,
        FavoriteModifier: favoriteModifier,
        RegisteredSelectionHotkeys: [],
        TabFallbackHotkeys: [],
        CancelButton: btnCancel
    }

    g_UnicodeInputGuiStates[guiObj.Hwnd] := state

    inputEdit.OnEvent("Change", UnicodeInput_UpdatePreview.Bind(guiObj))
    btnApply.OnEvent("Click", UnicodeInput_SubmitGui.Bind(guiObj))
    btnCancel.OnEvent("Click", UnicodeInput_CloseGui.Bind(guiObj))
    confirmSelectionChk.OnEvent("Click", UnicodeInput_SettingsChanged.Bind(guiObj, "ConfirmSelection"))
    moveHistoryChk.OnEvent("Click", UnicodeInput_SettingsChanged.Bind(guiObj, "MoveHistory"))
    historyModifierDDL.OnEvent("Change", UnicodeInput_SettingsChanged.Bind(guiObj, "HistoryModifier"))
    favoriteModifierDDL.OnEvent("Change", UnicodeInput_SettingsChanged.Bind(guiObj, "FavoriteModifier"))

    guiObj.OnEvent("Close", (*) => UnicodeInput_CloseGui(guiObj))

    UnicodeInput_RegisterGuiHotkeys(guiObj)

    guiObj.Show("w580 h" windowHeight)
    inputEdit.Focus()
}


UnicodeInput_SubmitGui(guiObj, *) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    input := Trim(state.Edit.Value)

    if (input = "") {
        state.Edit.Focus()
        return
    }

    codes := UnicodeInput_ParseCodes(input)

    if !IsObject(codes) || (codes.Length = 0) {
        SoundBeep(750, 120)
        Notify("Некорректный Unicode HEX-код", "Unicode Input", "Icon!")
        state.Edit.Focus()
        return
    }

    text := UnicodeInput_CodesToText(codes)

    if (text = "") {
        SoundBeep(750, 120)
        Notify("Не удалось преобразовать Unicode-код", "Unicode Input", "Icon!")
        state.Edit.Focus()
        return
    }

    UnicodeInput_ApplyAndClose(guiObj, text, codes)
}


UnicodeInput_UpdatePreview(guiObj, *) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    input := Trim(state.Edit.Value)

    if (input = "") {
        state.PreviewText.Text := ""
        return
    }

    codes := UnicodeInput_ParseCodes(input)

    if !IsObject(codes) || (codes.Length = 0) {
        state.PreviewText.Text := "…"
        return
    }

    preview := UnicodeInput_CodesPreview(codes)

    if (preview = "") {
        state.PreviewText.Text := "…"
        return
    }

    ; Чтобы длинный паттерн не разносил окно визуально.
    if (StrLen(preview) > 12) {
        preview := SubStr(preview, 1, 12) "…"
    }

    state.PreviewText.Text := UnicodeInput_EscapeGuiText(preview)
}


UnicodeInput_ApplyHistory(guiObj, index, *) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    if (index < 1 || index > state.History.Length) {
        SoundBeep(750, 120)
        return
    }

    hex := state.History[index]
    codes := [hex]
    text := UnicodeInput_CodesToText(codes)

    if (text = "") {
        SoundBeep(750, 120)
        return
    }

    UnicodeInput_ApplyAndClose(guiObj, text, codes)
}


UnicodeInput_ApplyFavorite(guiObj, index, *) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    if (index < 1 || index > state.Favorites.Length) {
        SoundBeep(750, 120)
        return
    }

    pattern := state.Favorites[index]
    codes := UnicodeInput_PatternToCodes(pattern)

    if !IsObject(codes) || (codes.Length = 0) {
        SoundBeep(750, 120)
        return
    }

    text := UnicodeInput_CodesToText(codes)

    if (text = "") {
        SoundBeep(750, 120)
        return
    }

    UnicodeInput_ApplyAndClose(guiObj, text, codes)
}


UnicodeInput_FocusHistory(guiObj, index, *) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    if (index < 1 || index > state.HistoryButtons.Length) {
        SoundBeep(750, 120)
        return
    }

    if (state.ConfirmSelectionChk.Value = 1) {
        state.HistoryButtons[index].Focus()
        return
    }

    UnicodeInput_ApplyHistory(guiObj, index)
}


UnicodeInput_FocusFavorite(guiObj, index, *) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    if (index < 1 || index > state.FavoriteButtons.Length) {
        SoundBeep(750, 120)
        return
    }

    if (state.ConfirmSelectionChk.Value = 1) {
        state.FavoriteButtons[index].Focus()
        return
    }

    UnicodeInput_ApplyFavorite(guiObj, index)
}


UnicodeInput_HandleEnter(guiObj, *) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    focusedHwnd := 0

    try {
        focusedClass := ControlGetFocus("ahk_id " guiObj.Hwnd)

        if (focusedClass != "") {
            focusedHwnd := ControlGetHwnd(focusedClass, "ahk_id " guiObj.Hwnd)
        }
    }

    if (focusedHwnd) {
        for index, btn in state.FavoriteButtons {
            if (focusedHwnd = btn.Hwnd) {
                UnicodeInput_ApplyFavorite(guiObj, index)
                return
            }
        }

        for index, btn in state.HistoryButtons {
            if (focusedHwnd = btn.Hwnd) {
                UnicodeInput_ApplyHistory(guiObj, index)
                return
            }
        }

        if (focusedHwnd = state.CancelButton.Hwnd) {
            UnicodeInput_CloseGui(guiObj)
            return
        }
    }

    UnicodeInput_SubmitGui(guiObj)
}


UnicodeInput_GetModifierChoices() {
    return ["Ctrl", "Shift", "Alt", "Win", "Tab"]
}


UnicodeInput_NormalizeShortcutModifier(value, fallback := "Ctrl") {
    value := StrLower(Trim(value))

    switch value {
        case "ctrl", "control":
            return "Ctrl"
        case "shift":
            return "Shift"
        case "alt":
            return "Alt"
        case "win", "windows":
            return "Win"
        case "tab":
            return "Tab"
        default:
            return fallback
    }
}


UnicodeInput_GetModifierIndex(modifier) {
    modifier := UnicodeInput_NormalizeShortcutModifier(modifier)

    for index, item in UnicodeInput_GetModifierChoices() {
        if (item = modifier) {
            return index
        }
    }

    return 1
}


UnicodeInput_ResolveShortcutModifiers(&historyModifier, &favoriteModifier) {
    historyModifier := UnicodeInput_NormalizeShortcutModifier(historyModifier, "Ctrl")
    favoriteModifier := UnicodeInput_NormalizeShortcutModifier(favoriteModifier, "Shift")

    if (historyModifier = favoriteModifier) {
        favoriteModifier := historyModifier = "Shift" ? "Ctrl" : "Shift"
    }
}


UnicodeInput_GetShortcutHotkey(modifier, index) {
    modifier := UnicodeInput_NormalizeShortcutModifier(modifier)

    switch modifier {
        case "Ctrl":
            return "^" index
        case "Shift":
            return "+" index
        case "Alt":
            return "!" index
        case "Win":
            return "#" index
        case "Tab":
            return "Tab & " index
    }

    return "^" index
}


UnicodeInput_GetShortcutDisplay(modifier) {
    return UnicodeInput_NormalizeShortcutModifier(modifier) "+1…5"
}


UnicodeInput_UpdateShortcutLabels(state) {
    if !IsObject(state) {
        return
    }

    if IsObject(state.FavoriteHeader) {
        state.FavoriteHeader.Text := "Избранное — быстрый выбор: " UnicodeInput_GetShortcutDisplay(state.FavoriteModifier)
    }

    if IsObject(state.HistoryHeader) {
        state.HistoryHeader.Text := "Недавние символы — быстрый выбор: " UnicodeInput_GetShortcutDisplay(state.HistoryModifier)
    }
}


UnicodeInput_SettingsChanged(guiObj, changedSetting, *) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    if (changedSetting = "ConfirmSelection") {
        UnicodeInput_SaveConfirmSelectionWithEnter(state.ConfirmSelectionChk.Value = 1)
    } else if (changedSetting = "MoveHistory") {
        UnicodeInput_SaveMoveHistoryOnUse(state.MoveHistoryChk.Value = 1)
    } else {
        newHistoryModifier := UnicodeInput_NormalizeShortcutModifier(state.HistoryModifierDDL.Text, state.HistoryModifier)
        newFavoriteModifier := UnicodeInput_NormalizeShortcutModifier(state.FavoriteModifierDDL.Text, state.FavoriteModifier)

        ; Если пользователь выбрал уже занятую клавишу, меняем назначения
        ; местами. Так Ctrl/Shift можно развернуть одним выбором.
        if (newHistoryModifier = newFavoriteModifier) {
            if (changedSetting = "HistoryModifier") {
                newFavoriteModifier := state.HistoryModifier
                state.FavoriteModifierDDL.Choose(UnicodeInput_GetModifierIndex(newFavoriteModifier))
            } else {
                newHistoryModifier := state.FavoriteModifier
                state.HistoryModifierDDL.Choose(UnicodeInput_GetModifierIndex(newHistoryModifier))
            }
        }

        UnicodeInput_SaveShortcutModifiers(newHistoryModifier, newFavoriteModifier)
    }

    UnicodeInput_RefreshOpenGuiSettings()
    try SettingsGui_UpdateUnicodeControls()
}


UnicodeInput_RegisterGuiHotkeys(guiObj) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    HotIfWinActive("ahk_id " guiObj.Hwnd)

    Loop 5 {
        historyHotkey := UnicodeInput_GetShortcutHotkey(state.HistoryModifier, A_Index)
        favoriteHotkey := UnicodeInput_GetShortcutHotkey(state.FavoriteModifier, A_Index)
        Hotkey(historyHotkey, UnicodeInput_FocusHistory.Bind(guiObj, A_Index), "On")
        Hotkey(favoriteHotkey, UnicodeInput_FocusFavorite.Bind(guiObj, A_Index), "On")
        state.RegisteredSelectionHotkeys.Push(historyHotkey)
        state.RegisteredSelectionHotkeys.Push(favoriteHotkey)
    }

    ; Once Tab has been used as a custom-combination prefix, AutoHotkey keeps
    ; intercepting it even after those combinations are disabled. Explicitly
    ; forward Tab whenever it is not assigned to history or favorites.
    if (state.HistoryModifier != "Tab" && state.FavoriteModifier != "Tab") {
        state.TabFallbackHotkeys := ["$Tab", "$+Tab"]
        Hotkey(state.TabFallbackHotkeys[1], UnicodeInput_ForwardTab.Bind(guiObj, false), "On")
        Hotkey(state.TabFallbackHotkeys[2], UnicodeInput_ForwardTab.Bind(guiObj, true), "On")
    }

    Hotkey("Enter", UnicodeInput_HandleEnter.Bind(guiObj), "On")
    Hotkey("Escape", UnicodeInput_CloseGui.Bind(guiObj), "On")

    HotIf()
}


UnicodeInput_UnregisterGuiHotkeys(guiObj) {
    state := UnicodeInput_GetGuiState(guiObj)

    HotIfWinActive("ahk_id " guiObj.Hwnd)

    if IsObject(state) {
        for hotkeyName in state.RegisteredSelectionHotkeys {
            try Hotkey(hotkeyName, "Off")
        }
        state.RegisteredSelectionHotkeys := []

        for hotkeyName in state.TabFallbackHotkeys {
            try Hotkey(hotkeyName, "Off")
        }
        state.TabFallbackHotkeys := []
    }

    try Hotkey("Enter", "Off")
    try Hotkey("Escape", "Off")

    HotIf()
}


UnicodeInput_ForwardTab(guiObj, reverse, *) {
    if IsObject(UnicodeInput_GetGuiState(guiObj)) {
        Send reverse ? "+{Tab}" : "{Tab}"
    }
}


UnicodeInput_GetGuiState(guiObj) {
    global g_UnicodeInputGuiStates

    if !IsObject(guiObj) {
        return ""
    }

    hwnd := guiObj.Hwnd

    if !g_UnicodeInputGuiStates.Has(hwnd) {
        return ""
    }

    return g_UnicodeInputGuiStates[hwnd]
}


UnicodeInput_CloseGui(guiObj, *) {
    global g_UnicodeInputGuiStates

    if !IsObject(guiObj) {
        return
    }

    hwnd := guiObj.Hwnd

    try UnicodeInput_UnregisterGuiHotkeys(guiObj)

    if g_UnicodeInputGuiStates.Has(hwnd) {
        g_UnicodeInputGuiStates.Delete(hwnd)
    }

    try guiObj.Destroy()
}


UnicodeInput_ApplyAndClose(guiObj, text, codes) {
    state := UnicodeInput_GetGuiState(guiObj)

    if !IsObject(state) {
        return
    }

    mode := state.Mode
    prevHwnd := state.PrevHwnd
    moveHistoryOnUse := state.MoveHistoryChk.Value = 1
    confirmSelectionWithEnter := state.ConfirmSelectionChk.Value = 1

    UnicodeInput_SaveMoveHistoryOnUse(moveHistoryOnUse)
    UnicodeInput_SaveConfirmSelectionWithEnter(confirmSelectionWithEnter)
    UnicodeInput_SaveShortcutModifiers(state.HistoryModifier, state.FavoriteModifier)
    UnicodeInput_UpdateHistory(codes, moveHistoryOnUse)
    UnicodeInput_UpdatePatternStats(codes)
    UnicodeInput_CloseGui(guiObj)

    if (mode = "insert" && prevHwnd) {
        try {
            if WinExist("ahk_id " prevHwnd) {
                WinActivate("ahk_id " prevHwnd)
                Sleep(60)
            }
        }
    }

    UnicodeInput_ApplyResult(text, mode)
}


UnicodeInput_ApplyResult(text, mode) {
    if (mode = "clipboard") {
        UnicodeInput_CopyToClipboard(text)
        return
    }

    SendText(text)
}


UnicodeInput_CopyToClipboard(text) {
    global g_AppName

    oldClipboard := ClipboardAll()

    try {
        A_Clipboard := ""
        A_Clipboard := text

        if !ClipWait(0.5) {
            A_Clipboard := oldClipboard
            Notify("Не удалось скопировать результат. Буфер обмена восстановлен", g_AppName " — Unicode Input", "Icon!")
            return
        }

        Notify("Скопировано в буфер обмена", g_AppName " — Unicode Input", "Iconi")
    } catch as err {
        try {
            A_Clipboard := oldClipboard
        }

        Notify("Не удалось скопировать результат: " err.Message, g_AppName " — Unicode Input", "Iconx")
    }
}


UnicodeHexToText(input) {
    codes := UnicodeInput_ParseCodes(input)

    if !IsObject(codes) || (codes.Length = 0) {
        return ""
    }

    return UnicodeInput_CodesToText(codes)
}


UnicodeInput_ParseCodes(input) {
    input := UnicodeInput_NormalizeKeyboardLayout(Trim(input))

    if (input = "") {
        return ""
    }

    ; Разрешаем только HEX-символы и пробельные разделители.
    ; Enter / перенос строки тоже попадает под \s, если такой текст вставлен в поле.
    if !RegExMatch(input, "i)^[0-9A-F\s]+$") {
        return ""
    }

    ; Если есть пробелы / переносы строк — считаем их явными разделителями кодов:
    ;   50 60 50 -> 0050, 0060, 0050
    if RegExMatch(input, "\s") {
        rawCodes := StrSplitByWhitespace(input)
    } else {
        rawCodes := []
        inputLength := StrLen(input)

        ; Если пользователь ввёл один короткий HEX-код и нажал Enter,
        ; считаем весь ввод одним Unicode code point:
        ;   AB -> 00AB
        ;   60 -> 0060
        ;   1F600 -> 1F600
        if (inputLength <= 6) {
            rawCodes.Push(input)
        } else {
            ; Длинный слитный ввод без разделителей оставляем старым удобным режимом:
            ;   005000600050 -> 0050, 0060, 0050
            ;
            ; Чтобы не гадать, длинная строка должна быть кратна 4.
            if (Mod(inputLength, 4) != 0) {
                return ""
            }

            Loop inputLength // 4 {
                rawCodes.Push(SubStr(input, ((A_Index - 1) * 4) + 1, 4))
            }
        }
    }

    codes := []

    for hex in rawCodes {
        hex := Trim(hex)

        if (hex = "") {
            continue
        }

        if !IsValidUnicodeHex(hex) {
            return ""
        }

        code := Integer("0x" hex)

        if !IsValidUnicodeCodepoint(code) {
            return ""
        }

        codes.Push(UnicodeInput_NormalizeCodepoint(code))
    }

    return codes
}


UnicodeInput_CodesToText(codes) {
    result := ""

    for hex in codes {
        code := Integer("0x" hex)

        if !IsValidUnicodeCodepoint(code) {
            return ""
        }

        result .= Chr(code)
    }

    return result
}


UnicodeInput_UpdateHistory(codes, moveExisting := true) {
    global g_UnicodeInputHistory

    UnicodeInput_LoadHistory()

    if moveExisting {
        for hex in codes {
            hex := UnicodeInput_NormalizeHex(hex)

            if (hex = "") {
                continue
            }

            UnicodeInput_RemoveFromHistory(hex)

            ; Последний использованный код должен быть выше.
            g_UnicodeInputHistory.InsertAt(1, hex)

            while (g_UnicodeInputHistory.Length > 5) {
                g_UnicodeInputHistory.Pop()
            }
        }

        UnicodeInput_SaveHistory()
        return
    }

    ; Режим без перемещения:
    ; существующие коды остаются на местах,
    ; наверх добавляются только новые коды.
    newCodes := []

    for hex in codes {
        hex := UnicodeInput_NormalizeHex(hex)

        if (hex = "") {
            continue
        }

        if UnicodeInput_HistoryHas(hex) {
            continue
        }

        if UnicodeInput_ArrayHas(newCodes, hex) {
            continue
        }

        newCodes.Push(hex)
    }

    insertIndex := 1

    for hex in newCodes {
        g_UnicodeInputHistory.InsertAt(insertIndex, hex)
        insertIndex += 1
    }

    while (g_UnicodeInputHistory.Length > 5) {
        g_UnicodeInputHistory.Pop()
    }

    UnicodeInput_SaveHistory()
}


UnicodeInput_RemoveFromHistory(hex) {
    global g_UnicodeInputHistory

    index := g_UnicodeInputHistory.Length

    while (index >= 1) {
        if (g_UnicodeInputHistory[index] = hex) {
            g_UnicodeInputHistory.RemoveAt(index)
        }

        index -= 1
    }
}


UnicodeInput_HistoryHas(hex) {
    global g_UnicodeInputHistory

    for oldHex in g_UnicodeInputHistory {
        if (oldHex = hex) {
            return true
        }
    }

    return false
}


UnicodeInput_ArrayHas(items, hex) {
    for item in items {
        if (item = hex) {
            return true
        }
    }

    return false
}


UnicodeInput_LoadHistory() {
    global g_ConfigPath
    global g_UnicodeInputHistory

    raw := ""

    try {
        raw := IniRead(g_ConfigPath, "UnicodeInput", "History", "")
    }

    history := []

    if (Trim(raw) != "") {
        for item in StrSplit(raw, ",") {
            hex := UnicodeInput_NormalizeHex(item)

            if (hex = "") {
                continue
            }

            exists := false

            for oldHex in history {
                if (oldHex = hex) {
                    exists := true
                    break
                }
            }

            if exists {
                continue
            }

            history.Push(hex)

            if (history.Length >= 5) {
                break
            }
        }
    }

    g_UnicodeInputHistory := history

    return g_UnicodeInputHistory.Clone()
}


UnicodeInput_LoadConfirmSelectionWithEnter() {
    global g_ConfigPath

    try {
        return IniRead(g_ConfigPath, "UnicodeInput", "ConfirmSelectionWithEnter", "1") = "1"
    }

    return true
}


UnicodeInput_SaveConfirmSelectionWithEnter(enabled) {
    global g_ConfigPath

    try IniWrite(enabled ? "1" : "0", g_ConfigPath, "UnicodeInput", "ConfirmSelectionWithEnter")
}


UnicodeInput_LoadMoveHistoryOnUse() {
    global g_ConfigPath

    try {
        return IniRead(g_ConfigPath, "UnicodeInput", "MoveHistoryOnUse", "1") = "1"
    }

    return true
}


UnicodeInput_SaveMoveHistoryOnUse(enabled) {
    global g_ConfigPath

    try IniWrite(enabled ? "1" : "0", g_ConfigPath, "UnicodeInput", "MoveHistoryOnUse")
}


UnicodeInput_LoadHistoryShortcutModifier() {
    global g_ConfigPath

    try {
        value := IniRead(g_ConfigPath, "UnicodeInput", "HistoryShortcutModifier", "Ctrl")
        return UnicodeInput_NormalizeShortcutModifier(value, "Ctrl")
    }

    return "Ctrl"
}


UnicodeInput_LoadFavoriteShortcutModifier() {
    global g_ConfigPath

    try {
        value := IniRead(g_ConfigPath, "UnicodeInput", "FavoriteShortcutModifier", "Shift")
        return UnicodeInput_NormalizeShortcutModifier(value, "Shift")
    }

    return "Shift"
}


UnicodeInput_SaveShortcutModifiers(historyModifier, favoriteModifier) {
    global g_ConfigPath

    historyModifier := UnicodeInput_NormalizeShortcutModifier(historyModifier, "Ctrl")
    favoriteModifier := UnicodeInput_NormalizeShortcutModifier(favoriteModifier, "Shift")

    if (historyModifier = favoriteModifier) {
        return false
    }

    try {
        IniWrite(historyModifier, g_ConfigPath, "UnicodeInput", "HistoryShortcutModifier")
        IniWrite(favoriteModifier, g_ConfigPath, "UnicodeInput", "FavoriteShortcutModifier")
        return true
    }

    return false
}


UnicodeInput_RefreshOpenGuiSettings() {
    global g_UnicodeInputGuiStates

    confirmSelectionWithEnter := UnicodeInput_LoadConfirmSelectionWithEnter()
    moveHistoryOnUse := UnicodeInput_LoadMoveHistoryOnUse()
    historyModifier := UnicodeInput_LoadHistoryShortcutModifier()
    favoriteModifier := UnicodeInput_LoadFavoriteShortcutModifier()
    UnicodeInput_ResolveShortcutModifiers(&historyModifier, &favoriteModifier)

    for _, state in g_UnicodeInputGuiStates {
        if !IsObject(state) || !IsObject(state.Gui) {
            continue
        }

        modifierChanged := state.HistoryModifier != historyModifier
            || state.FavoriteModifier != favoriteModifier

        if modifierChanged {
            try UnicodeInput_UnregisterGuiHotkeys(state.Gui)
        }

        state.ConfirmSelectionChk.Value := confirmSelectionWithEnter ? 1 : 0
        state.MoveHistoryChk.Value := moveHistoryOnUse ? 1 : 0
        state.HistoryModifier := historyModifier
        state.FavoriteModifier := favoriteModifier
        state.HistoryModifierDDL.Choose(UnicodeInput_GetModifierIndex(historyModifier))
        state.FavoriteModifierDDL.Choose(UnicodeInput_GetModifierIndex(favoriteModifier))
        UnicodeInput_UpdateShortcutLabels(state)

        if modifierChanged {
            try UnicodeInput_RegisterGuiHotkeys(state.Gui)
        }
    }

    try LTWebUnicodeInput.RefreshSettings()
}


UnicodeInput_SaveHistory() {
    global g_ConfigPath
    global g_UnicodeInputHistory

    historyText := ""

    for hex in g_UnicodeInputHistory {
        historyText .= (historyText = "" ? "" : ",") hex
    }

    try IniWrite(historyText, g_ConfigPath, "UnicodeInput", "History")
}


UnicodeInput_GetHistory() {
    global g_UnicodeInputHistory

    UnicodeInput_LoadHistory()
    return g_UnicodeInputHistory.Clone()
}


UnicodeInput_UpdatePatternStats(codes) {
    if !IsObject(codes) || (codes.Length < 2) {
        return
    }

    pattern := UnicodeInput_CodesToPattern(codes)

    if (pattern = "") {
        return
    }

    stats := UnicodeInput_LoadPatternStats()

    current := stats.Has(pattern) ? stats[pattern] : 0
    stats[pattern] := current + 1

    UnicodeInput_SavePatternStats(stats)
}


UnicodeInput_LoadPatternStats() {
    global g_ConfigPath

    raw := ""

    try {
        raw := IniRead(g_ConfigPath, "UnicodeInput", "PatternStats", "")
    }

    stats := Map()

    if (Trim(raw) = "") {
        return stats
    }

    for item in StrSplit(raw, ",") {
        item := Trim(item)

        if (item = "") {
            continue
        }

        parts := StrSplit(item, ":")

        if (parts.Length != 2) {
            continue
        }

        pattern := UnicodeInput_NormalizePattern(parts[1])
        countText := Trim(parts[2])

        if (pattern = "") {
            continue
        }

        if !RegExMatch(countText, "^\d+$") {
            continue
        }

        count := Integer(countText)

        if (count < 1) {
            continue
        }

        stats[pattern] := count
    }

    return stats
}


UnicodeInput_SavePatternStats(stats) {
    global g_ConfigPath

    items := []

    for pattern, count in stats {
        pattern := UnicodeInput_NormalizePattern(pattern)

        if (pattern = "") {
            continue
        }

        if (count < 1) {
            continue
        }

        items.Push({ Pattern: pattern, Count: count })
    }

    UnicodeInput_SortPatternItems(items)

    ; Не даём settings.ini разрастаться бесконечно.
    while (items.Length > 30) {
        items.Pop()
    }

    raw := ""

    for item in items {
        raw .= (raw = "" ? "" : ",") item.Pattern ":" item.Count
    }

    try IniWrite(raw, g_ConfigPath, "UnicodeInput", "PatternStats")
}


UnicodeInput_GetAutoFavorites() {
    global g_ConfigPath

    minUses := 2
    maxFavorites := 5

    try {
        rawMinUses := IniRead(g_ConfigPath, "UnicodeInput", "AutoFavoritesMinUses", "2")
        if RegExMatch(rawMinUses, "^\d+$") {
            minUses := Max(1, Integer(rawMinUses))
        }
    }

    try {
        rawMaxFavorites := IniRead(g_ConfigPath, "UnicodeInput", "AutoFavoritesMax", "5")
        if RegExMatch(rawMaxFavorites, "^\d+$") {
            maxFavorites := Max(1, Min(10, Integer(rawMaxFavorites)))
        }
    }

    stats := UnicodeInput_LoadPatternStats()

    items := []

    for pattern, count in stats {
        if (count < minUses) {
            continue
        }

        if (UnicodeInput_PatternLength(pattern) < 2) {
            continue
        }

        items.Push({ Pattern: pattern, Count: count })
    }

    UnicodeInput_SortPatternItems(items)

    favorites := []

    for item in items {
        favorites.Push(item.Pattern)

        if (favorites.Length >= maxFavorites) {
            break
        }
    }

    return favorites
}


UnicodeInput_SortPatternItems(items) {
    if (items.Length < 2) {
        return
    }

    Loop items.Length - 1 {
        i := A_Index
        j := i + 1

        while (j <= items.Length) {
            if (items[j].Count > items[i].Count) {
                tmp := items[i]
                items[i] := items[j]
                items[j] := tmp
            }

            j += 1
        }
    }
}


UnicodeInput_CodesToPattern(codes) {
    pattern := ""

    for hex in codes {
        hex := UnicodeInput_NormalizeHex(hex)

        if (hex = "") {
            return ""
        }

        pattern .= (pattern = "" ? "" : "-") hex
    }

    return pattern
}


UnicodeInput_PatternToCodes(pattern) {
    pattern := UnicodeInput_NormalizePattern(pattern)

    if (pattern = "") {
        return ""
    }

    codes := []

    for hex in StrSplit(pattern, "-") {
        hex := UnicodeInput_NormalizeHex(hex)

        if (hex = "") {
            return ""
        }

        codes.Push(hex)
    }

    return codes
}


UnicodeInput_NormalizePattern(pattern) {
    pattern := Trim(pattern)

    if (pattern = "") {
        return ""
    }

    codes := []

    for hex in StrSplit(pattern, "-") {
        hex := UnicodeInput_NormalizeHex(hex)

        if (hex = "") {
            return ""
        }

        codes.Push(hex)
    }

    if (codes.Length < 2) {
        return ""
    }

    return UnicodeInput_CodesToPattern(codes)
}


UnicodeInput_PatternLength(pattern) {
    pattern := UnicodeInput_NormalizePattern(pattern)

    if (pattern = "") {
        return 0
    }

    return StrSplit(pattern, "-").Length
}


UnicodeInput_CodesPreview(codes) {
    result := ""

    for hex in codes {
        hex := UnicodeInput_NormalizeHex(hex)

        if (hex = "") {
            return ""
        }

        result .= UnicodeInput_CodePreviewInline(hex)
    }

    return result
}


UnicodeInput_EscapeGuiText(text) {
    return StrReplace(text, "&", "&&")
}


UnicodeInput_PatternPreview(pattern) {
    codes := UnicodeInput_PatternToCodes(pattern)

    if !IsObject(codes) || (codes.Length = 0) {
        return ""
    }

    result := ""

    for hex in codes {
        result .= UnicodeInput_CodePreviewInline(hex)
    }

    return result
}


UnicodeInput_CodePreviewInline(hex) {
    code := Integer("0x" hex)

    switch code {
        case 0x0009:
            return "[TAB]"
        case 0x000A:
            return "[LF]"
        case 0x000D:
            return "[CR]"
        case 0x0020:
            return "␠"
        default:
            return Chr(code)
    }
}


UnicodeInput_NormalizeKeyboardLayout(text) {
    ; Если HEX введён в русской раскладке, воспринимаем символы как клавиши EN.
    ; Для Unicode Input достаточно HEX-букв A-F:
    ;   ф -> A
    ;   и -> B
    ;   с -> C
    ;   в -> D
    ;   у -> E
    ;   а -> F
    ;
    ; Примеры:
    ;   фи -> AB
    ;   ф00и -> A00B
    ;   60 -> 60
    ;
    ; Это именно физическая QWERTY-раскладка, а не визуальная похожесть букв.
    text := StrReplace(text, "ф", "a")
    text := StrReplace(text, "Ф", "A")

    text := StrReplace(text, "и", "b")
    text := StrReplace(text, "И", "B")

    text := StrReplace(text, "с", "c")
    text := StrReplace(text, "С", "C")

    text := StrReplace(text, "в", "d")
    text := StrReplace(text, "В", "D")

    text := StrReplace(text, "у", "e")
    text := StrReplace(text, "У", "E")

    text := StrReplace(text, "а", "f")
    text := StrReplace(text, "А", "F")

    return text
}


UnicodeInput_NormalizeHex(hex) {
    hex := Trim(hex)

    if (hex = "") {
        return ""
    }

    if !IsValidUnicodeHex(hex) {
        return ""
    }

    code := Integer("0x" hex)

    if !IsValidUnicodeCodepoint(code) {
        return ""
    }

    return UnicodeInput_NormalizeCodepoint(code)
}


UnicodeInput_NormalizeCodepoint(code) {
    if (code <= 0xFFFF) {
        return Format("{:04X}", code)
    }

    return Format("{:06X}", code)
}


UnicodeInput_CodePreview(hex) {
    code := Integer("0x" hex)

    switch code {
        case 0x0009:
            return "[TAB]"
        case 0x000A:
            return "[LF]"
        case 0x000D:
            return "[CR]"
        case 0x0020:
            return "[SPACE]"
        default:
            return Chr(code)
    }
}


StrSplitByWhitespace(text) {
    parts := []

    for part in StrSplit(RegExReplace(text, "\s+", " "), " ") {
        part := Trim(part)

        if (part != "") {
            parts.Push(part)
        }
    }

    return parts
}


IsValidUnicodeHex(hex) {
    return RegExMatch(hex, "i)^[0-9A-F]{1,6}$")
}


IsValidUnicodeCodepoint(code) {
    if (code < 1 || code > 0x10FFFF) {
        return false
    }

    ; Суррогатная зона UTF-16, невалидна как самостоятельный Unicode code point.
    if (code >= 0xD800 && code <= 0xDFFF) {
        return false
    }

    return true
}
