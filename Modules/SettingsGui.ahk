; SettingsGui.ahk
; Окно настроек Layout Toolkit.
;
; Здесь находится GUI настроек:
; - левая навигация по разделам
; - текстовые страницы состояния и описания функций
; - служебные кнопки для открытия файлов, перезагрузки настроек и сброса значений
; - версия читается из CHANGELOG.md
;
; Основная логика функций остаётся в главном скрипте и модулях.


g_SettingsGui := ""
g_SettingsContentTitle := ""
g_SettingsContentBody := ""

g_SettingsActionBtn1 := ""
g_SettingsActionBtn2 := ""
g_SettingsActionBtn3 := ""

g_SettingsLiveEnabledChk := ""
g_SettingsLiveSpaceRadio := ""
g_SettingsLiveHotkeyRadio := ""
g_SettingsLiveDoubleSpaceLabel := ""
g_SettingsLiveDoubleSpaceEdit := ""
g_SettingsLiveDoubleSpaceHint := ""
g_SettingsLiveHintChk := ""

g_SettingsUnicodeConfirmChk := ""
g_SettingsUnicodeMoveHistoryChk := ""
g_SettingsUnicodeHistoryModifierDDL := ""
g_SettingsUnicodeFavoriteModifierDDL := ""
g_SettingsUnicodeControls := []
g_SettingsUnicodePreviousHistoryModifier := "Ctrl"
g_SettingsUnicodePreviousFavoriteModifier := "Shift"

g_SettingsHotkeyEdits := Map()
g_SettingsHotkeyCaptureButtons := []
g_SettingsHotkeySaveBtn := ""
g_SettingsPendingHotkeys := Map()
g_HotkeyCaptureActive := false
g_HotkeyCaptureModifiers := Map()


OpenNativeSettingsGui(*) {
    global g_SettingsGui, g_SettingsContentTitle, g_SettingsContentBody
    global g_SettingsActionBtn1, g_SettingsActionBtn2, g_SettingsActionBtn3
    global g_SettingsLiveEnabledChk, g_SettingsLiveDoubleSpaceLabel, g_SettingsLiveDoubleSpaceEdit
    global g_SettingsLiveDoubleSpaceHint, g_SettingsLiveHintChk
    global g_SettingsLiveSpaceRadio, g_SettingsLiveHotkeyRadio
    global g_SettingsUnicodeConfirmChk, g_SettingsUnicodeMoveHistoryChk
    global g_SettingsUnicodeHistoryModifierDDL, g_SettingsUnicodeFavoriteModifierDDL
    global g_SettingsUnicodeControls
    global g_SettingsHotkeyEdits, g_SettingsHotkeyCaptureButtons, g_SettingsHotkeySaveBtn
    global g_AppName

    if IsObject(g_SettingsGui) {
        try {
            g_SettingsGui.Show()
            SettingsGui_ShowPage("General")
            return
        }
    }

    g_SettingsGui := Gui("-Resize", g_AppName " — Настройки")
    g_SettingsGui.SetFont("s9", "Segoe UI")

    g_SettingsGui.OnEvent("Close", SettingsGui_OnClose)
    g_SettingsGui.OnEvent("Escape", SettingsGui_OnClose)

    navX := 12
    navY := 12
    navW := 150
    btnH := 30
    gap := 6

    SettingsGui_AddNavButton("Общее", "General", navX, navY, navW, btnH)
    navY += btnH + gap

    SettingsGui_AddNavButton("Layout Fix", "LayoutFix", navX, navY, navW, btnH)
    navY += btnH + gap

    SettingsGui_AddNavButton("Live-режим", "Live", navX, navY, navW, btnH)
    navY += btnH + gap

    SettingsGui_AddNavButton("Горячие клавиши", "Hotkeys", navX, navY, navW, btnH)
    navY += btnH + gap

    SettingsGui_AddNavButton("Unicode Input", "Unicode", navX, navY, navW, btnH)
    navY += btnH + gap

    SettingsGui_AddNavButton("CapsLock Fix", "CapsLock", navX, navY, navW, btnH)
    navY += btnH + gap

    SettingsGui_AddNavButton("Исключения", "Exclusions", navX, navY, navW, btnH)
    navY += btnH + gap

    SettingsGui_AddNavButton("О программе", "About", navX, navY, navW, btnH)

    g_SettingsContentTitle := g_SettingsGui.AddText("x180 y14 w560 h28", "")
    g_SettingsContentTitle.SetFont("s12 bold")

    g_SettingsContentBody := g_SettingsGui.AddEdit("x180 y48 w560 h340 ReadOnly +Wrap VScroll", "")
    g_SettingsContentBody.SetFont("s9", "Segoe UI")

    g_SettingsLiveEnabledChk := g_SettingsGui.AddCheckbox("x180 y268 w520 h24 Hidden", "Включить Live-режим")
    g_SettingsLiveSpaceRadio := g_SettingsGui.AddRadio("x180 y296 w520 h24 Hidden Group", "Запускать двойным пробелом")
    g_SettingsLiveHotkeyRadio := g_SettingsGui.AddRadio("x180 y324 w520 h24 Hidden", "Запускать горячей клавишей")
    g_SettingsLiveSpaceRadio.OnEvent("Click", SettingsGui_LiveTriggerChanged)
    g_SettingsLiveHotkeyRadio.OnEvent("Click", SettingsGui_LiveTriggerChanged)
    g_SettingsLiveDoubleSpaceLabel := g_SettingsGui.AddText("x180 y356 w210 h23 Hidden", "Интервал между пробелами:")
    g_SettingsLiveDoubleSpaceEdit := g_SettingsGui.AddEdit("x395 y352 w90 h24 Number Hidden", "")
    g_SettingsLiveDoubleSpaceHint := g_SettingsGui.AddText("x495 y356 w190 h23 Hidden", "100–3000 мс")
    g_SettingsLiveHintChk := g_SettingsGui.AddCheckbox("x180 y382 w540 h24 Hidden", "Показывать подробную подсказку при первом включении Live-режима")

    g_SettingsUnicodeConfirmChk := g_SettingsGui.AddCheckbox("x180 y260 w540 h24 Hidden", "Подтверждать быстрый выбор клавишей Enter")
    g_SettingsUnicodeMoveHistoryChk := g_SettingsGui.AddCheckbox("x180 y290 w540 h24 Hidden", "Поднимать использованный символ в начало истории")

    unicodeHistoryLabel := g_SettingsGui.AddText("x180 y328 w215 h24 Hidden", "Быстрый выбор истории:")
    g_SettingsUnicodeHistoryModifierDDL := g_SettingsGui.AddDropDownList("x400 y324 w105 Hidden", UnicodeInput_GetModifierChoices())
    unicodeHistorySuffix := g_SettingsGui.AddText("x515 y328 w80 h24 Hidden", "+ 1…5")

    unicodeFavoriteLabel := g_SettingsGui.AddText("x180 y360 w215 h24 Hidden", "Быстрый выбор избранного:")
    g_SettingsUnicodeFavoriteModifierDDL := g_SettingsGui.AddDropDownList("x400 y356 w105 Hidden", UnicodeInput_GetModifierChoices())
    unicodeFavoriteSuffix := g_SettingsGui.AddText("x515 y360 w80 h24 Hidden", "+ 1…5")

    g_SettingsUnicodeHistoryModifierDDL.OnEvent("Change", SettingsGui_UnicodeModifierChanged.Bind("HistoryModifier"))
    g_SettingsUnicodeFavoriteModifierDDL.OnEvent("Change", SettingsGui_UnicodeModifierChanged.Bind("FavoriteModifier"))
    g_SettingsUnicodeControls := [
        g_SettingsUnicodeConfirmChk,
        g_SettingsUnicodeMoveHistoryChk,
        unicodeHistoryLabel,
        g_SettingsUnicodeHistoryModifierDDL,
        unicodeHistorySuffix,
        unicodeFavoriteLabel,
        g_SettingsUnicodeFavoriteModifierDDL,
        unicodeFavoriteSuffix
    ]

    hotkeyRows := [
        ["LayoutFull", "Полное исправление"],
        ["LayoutMajority", "Исправление по большинству"],
        ["LiveToggle", "Включить или выключить Live"],
        ["LiveConvert", "Исправить текущий Live-фрагмент"],
        ["UnicodeInput", "Unicode Input"],
        ["CapsLockFix", "CapsLock Fix (умный)"],
        ["CapsLockFullFix", "CapsLock Full Fix"]
    ]
    hotkeyY := 108

    for _, row in hotkeyRows {
        actionName := row[1]
        label := row[2]
        labelCtrl := g_SettingsGui.AddText("x180 y" (hotkeyY + 5) " w220 h24 Hidden", label)
        editCtrl := g_SettingsGui.AddEdit("x405 y" hotkeyY " w165 h25 ReadOnly Center Hidden", "")
        captureBtn := g_SettingsGui.AddButton("x580 y" hotkeyY " w110 h25 Hidden", "Захватить")
        captureBtn.OnEvent("Click", SettingsGui_CaptureHotkey.Bind(actionName))
        g_SettingsHotkeyEdits[actionName] := editCtrl
        g_SettingsHotkeyCaptureButtons.Push(labelCtrl)
        g_SettingsHotkeyCaptureButtons.Push(captureBtn)
        hotkeyY += 38
    }

    g_SettingsHotkeySaveBtn := g_SettingsGui.AddButton("x180 y376 w165 h30 Hidden", "Сохранить сочетания")
    g_SettingsHotkeySaveBtn.OnEvent("Click", SettingsGui_SaveCapturedHotkeys)

    g_SettingsActionBtn1 := g_SettingsGui.AddButton("x180 y420 w165 h30 Hidden", "")
    g_SettingsActionBtn1.OnEvent("Click", SettingsGui_ActionButton1)
    
    g_SettingsActionBtn2 := g_SettingsGui.AddButton("x355 y420 w165 h30 Hidden", "")
    g_SettingsActionBtn2.OnEvent("Click", SettingsGui_ActionButton2)
    
    g_SettingsActionBtn3 := g_SettingsGui.AddButton("x530 y420 w165 h30 Hidden", "")
    g_SettingsActionBtn3.OnEvent("Click", SettingsGui_ActionButton3)
    
    closeBtn := g_SettingsGui.AddButton("x650 y462 w90 h30", "Закрыть")
    closeBtn.OnEvent("Click", SettingsGui_Close)

    SettingsGui_ShowPage("General")

    g_SettingsGui.Show("w760 h505")
}


SettingsGui_AddNavButton(label, pageName, x, y, w, h) {
    global g_SettingsGui

    btn := g_SettingsGui.AddButton("x" x " y" y " w" w " h" h, label)
    btn.OnEvent("Click", (*) => SettingsGui_ShowPage(pageName))
}


SettingsGui_ShowPage(pageName, *) {
    global g_SettingsContentTitle, g_SettingsContentBody

    title := ""
    body := ""

    switch pageName {
        case "General":
            title := "Общее"
            body := SettingsGui_GetGeneralText()

        case "LayoutFix":
            title := "Layout Fix"
            body := SettingsGui_GetLayoutFixText()

        case "Live":
            title := "Live-режим"
            body := SettingsGui_GetLiveText()

        case "Hotkeys":
            title := "Горячие клавиши"
            body := SettingsGui_GetHotkeysText()

        case "Unicode":
            title := "Unicode Input"
            body := SettingsGui_GetUnicodeText()

        case "CapsLock":
            title := "CapsLock Fix"
            body := SettingsGui_GetCapsLockText()

        case "Exclusions":
            title := "Исключения"
            body := SettingsGui_GetExclusionsText()

        case "About":
            title := "О программе"
            body := SettingsGui_GetAboutText()

        default:
            title := "Layout Toolkit"
            body := "Неизвестный раздел: " pageName
    }

    g_SettingsContentTitle.Text := title
    g_SettingsContentBody.Value := body

    SettingsGui_ApplyPageLayout(pageName)
    SettingsGui_SetLiveControlsVisible(pageName = "Live")
    SettingsGui_SetHotkeyControlsVisible(pageName = "Hotkeys")
    SettingsGui_SetUnicodeControlsVisible(pageName = "Unicode")

    if (pageName = "Live") {
        SettingsGui_UpdateLiveControls()
    } else if (pageName = "Hotkeys") {
        SettingsGui_UpdateHotkeyControls()
    } else if (pageName = "Unicode") {
        SettingsGui_UpdateUnicodeControls()
    }
    
    switch pageName {
        case "General":
            SettingsGui_SetActions(
                "Открыть папку данных", "OpenDataDir",
                "Перезапустить", "RestartToolkit"
            )
			
        case "Live":
            SettingsGui_SetActions(
                "Сохранить", "SaveLiveSettings"
            )

        case "Hotkeys":
            SettingsGui_SetActions(
                "Открыть файл", "OpenHotkeysFile",
                "Загрузить из файла", "ReloadHotkeys",
                "Сбросить", "RestoreDefaultHotkeys"
            )
			
        case "Unicode":
            SettingsGui_SetActions(
                "Сохранить", "SaveUnicodeSettings",
                "Открыть режим копирования", "OpenUnicodeInputClipboard"
            )

        case "Exclusions":
            SettingsGui_SetActions(
                "Открыть словарь", "OpenExcludeFile",
                "Применить изменения", "ReloadExcludeWords",
                "Сбросить", "RestoreDefaultExcludeWords"
            )
    
        default:
            SettingsGui_SetActions()
    }
}


SettingsGui_GetGeneralText() {
    global g_ConfigDir
    global g_LiveEnabled, g_ShowTrayTips, g_PlaySound

    text := ""
    text .= "Состояние`r`n"
    text .= "Layout Toolkit запущен.`r`n"
    text .= "Live-режим: " SettingsGui_OnOff(g_LiveEnabled) "`r`n"
    text .= "Уведомления: " SettingsGui_OnOff(g_ShowTrayTips) "`r`n"
    text .= "Звук уведомлений: " SettingsGui_OnOff(g_PlaySound) "`r`n"
    text .= "`r`n"

    text .= "Layout Toolkit работает в фоне. Основные функции доступны через горячие клавиши и меню в трее.`r`n"
    text .= "Двойной щелчок по значку в трее открывает это окно.`r`n"
    text .= "`r`n"

    text .= "Папка с вашими настройками:`r`n"
    text .= g_ConfigDir "`r`n"

    return text
}


SettingsGui_GetLayoutFixText() {
    global g_HotkeyLayoutFull, g_HotkeyLayoutMajority, g_HotkeyLiveToggle, g_HotkeyLiveConvert

    text := ""
    text .= "Layout Fix исправляет выделенный текст, набранный в неправильной RU/EN-раскладке.`r`n"
    text .= "`r`n"

    text .= "Полное исправление`r`n"
    text .= "Определяет направление отдельно для каждого слова и меняет символы на соответствующие клавиши другой раскладки.`r`n"
    text .= "В однозначно русском или английском слове все символы, включая пунктуацию, меняются строго по физическим клавишам. Словарь исключений продолжает действовать.`r`n"
    text .= "Горячая клавиша: " HotkeyToDisplay(g_HotkeyLayoutFull) "`r`n"
    text .= "`r`n"

    text .= "Исправление по большинству`r`n"
    text .= "Подходит для смешанного текста: меняет только фрагменты, похожие на ошибочную раскладку.`r`n"
    text .= "Горячая клавиша: " HotkeyToDisplay(g_HotkeyLayoutMajority) "`r`n"
    text .= "`r`n"

    text .= "Live-режим`r`n"
    text .= "Исправляет текущий фрагмент во время набора. Запуск — двойным пробелом или альтернативным хоткеем.`r`n"
    text .= "Переключение: " HotkeyToDisplay(g_HotkeyLiveToggle) "`r`n"
    text .= "Альтернативный хоткей исправления: " HotkeyToDisplay(g_HotkeyLiveConvert) "`r`n"
    text .= "`r`n"

    text .= "Изменить горячие клавиши можно в разделе “Горячие клавиши”.`r`n"

    return text
}


SettingsGui_GetLiveText() {
    global g_LiveEnabled, g_LiveTriggerMode, g_HotkeyLiveToggle, g_HotkeyLiveConvert
    global g_DoubleSpaceMs, g_ShowFirstToggleHint

    text := ""
    text .= "Live-режим сейчас: " SettingsGui_OnOff(g_LiveEnabled) "`r`n"
    text .= "Хоткей переключения: " HotkeyToDisplay(g_HotkeyLiveToggle) "`r`n"
    text .= "Выбранный запуск: " (g_LiveTriggerMode = "Hotkey" ? "по горячей клавише" : "по двойному пробелу") "`r`n"
    text .= "`r`n"
    text .= "Двойной пробел исправляет текущий фрагмент и оставляет после него один пробел.`r`n"
    text .= "Горячая клавиша " HotkeyToDisplay(g_HotkeyLiveConvert) " исправляет текущий фрагмент и ничего не добавляет в конец.`r`n"
    text .= "Это альтернативные способы запуска: одновременно действует только выбранный вариант.`r`n"
    text .= "`r`n"
    text .= "Подсказка при первом включении: " SettingsGui_OnOff(g_ShowFirstToggleHint) "`r`n"
    text .= "`r`n"
    text .= "Live-режим рассчитан на короткие фрагменты во время набора. Для больших выделений используйте Layout Fix.`r`n"

    return text
}

SettingsGui_ApplyPageLayout(pageName) {
    global g_SettingsContentBody

    if !IsObject(g_SettingsContentBody) {
        return
    }

    if (pageName = "Live") {
        g_SettingsContentBody.Move(180, 48, 560, 205)
    } else if (pageName = "Hotkeys") {
        g_SettingsContentBody.Move(180, 48, 560, 48)
    } else if (pageName = "Unicode") {
        g_SettingsContentBody.Move(180, 48, 560, 195)
    } else {
        g_SettingsContentBody.Move(180, 48, 560, 340)
    }
}

SettingsGui_SetLiveControlsVisible(visible) {
    global g_SettingsLiveEnabledChk, g_SettingsLiveDoubleSpaceLabel, g_SettingsLiveDoubleSpaceEdit
    global g_SettingsLiveDoubleSpaceHint, g_SettingsLiveHintChk
    global g_SettingsLiveSpaceRadio, g_SettingsLiveHotkeyRadio

    controls := [
        g_SettingsLiveEnabledChk,
        g_SettingsLiveSpaceRadio,
        g_SettingsLiveHotkeyRadio,
        g_SettingsLiveDoubleSpaceLabel,
        g_SettingsLiveDoubleSpaceEdit,
        g_SettingsLiveDoubleSpaceHint,
        g_SettingsLiveHintChk
    ]

    for _, ctrl in controls {
        if IsObject(ctrl) {
            ctrl.Visible := visible
        }
    }

    if visible {
        SettingsGui_UpdateLiveTriggerControlVisibility()
    }
}


SettingsGui_LiveTriggerChanged(*) {
    SettingsGui_UpdateLiveTriggerControlVisibility()
}


SettingsGui_UpdateLiveTriggerControlVisibility() {
    global g_SettingsLiveEnabledChk, g_SettingsLiveSpaceRadio
    global g_SettingsLiveDoubleSpaceLabel, g_SettingsLiveDoubleSpaceEdit, g_SettingsLiveDoubleSpaceHint

    pageVisible := IsObject(g_SettingsLiveEnabledChk) && g_SettingsLiveEnabledChk.Visible
    showInterval := pageVisible && IsObject(g_SettingsLiveSpaceRadio) && g_SettingsLiveSpaceRadio.Value = 1

    for _, ctrl in [g_SettingsLiveDoubleSpaceLabel, g_SettingsLiveDoubleSpaceEdit, g_SettingsLiveDoubleSpaceHint] {
        if IsObject(ctrl) {
            ctrl.Visible := showInterval
        }
    }
}


SettingsGui_UpdateLiveControls() {
    global g_SettingsLiveEnabledChk, g_SettingsLiveDoubleSpaceEdit, g_SettingsLiveHintChk
    global g_SettingsLiveSpaceRadio, g_SettingsLiveHotkeyRadio
    global g_LiveEnabled, g_LiveTriggerMode, g_DoubleSpaceMs, g_ShowFirstToggleHint
    global g_HotkeyLiveConvert

    if IsObject(g_SettingsLiveEnabledChk) {
        g_SettingsLiveEnabledChk.Value := g_LiveEnabled ? 1 : 0
    }

    if IsObject(g_SettingsLiveDoubleSpaceEdit) {
        g_SettingsLiveDoubleSpaceEdit.Value := g_DoubleSpaceMs
    }

    if IsObject(g_SettingsLiveSpaceRadio) {
        g_SettingsLiveSpaceRadio.Value := g_LiveTriggerMode = "DoubleSpace" ? 1 : 0
    }

    if IsObject(g_SettingsLiveHotkeyRadio) {
        g_SettingsLiveHotkeyRadio.Value := g_LiveTriggerMode = "Hotkey" ? 1 : 0
        g_SettingsLiveHotkeyRadio.Text := "Запускать горячей клавишей (" HotkeyToDisplay(g_HotkeyLiveConvert) ")"
    }

    if IsObject(g_SettingsLiveHintChk) {
        g_SettingsLiveHintChk.Value := g_ShowFirstToggleHint ? 1 : 0
    }

    SettingsGui_UpdateLiveTriggerControlVisibility()
}


SettingsGui_SaveLiveSettings() {
    global g_SettingsLiveEnabledChk, g_SettingsLiveDoubleSpaceEdit, g_SettingsLiveHintChk
    global g_SettingsLiveSpaceRadio, g_SettingsLiveHotkeyRadio
    global g_ConfigPath, g_LiveTriggerMode, g_DoubleSpaceMs, g_ShowFirstToggleHint, g_AppName
    global g_LiveBusy

    if (!IsObject(g_SettingsLiveEnabledChk)
     || !IsObject(g_SettingsLiveDoubleSpaceEdit)
     || !IsObject(g_SettingsLiveHintChk)
     || !IsObject(g_SettingsLiveSpaceRadio)
     || !IsObject(g_SettingsLiveHotkeyRadio)) {
        return
    }

    if g_LiveBusy {
        Notify("Дождитесь завершения текущего Live-исправления и повторите сохранение", g_AppName, "Icon!")
        return
    }

    newTriggerMode := g_SettingsLiveHotkeyRadio.Value = 1 ? "Hotkey" : "DoubleSpace"
    newDoubleSpaceMs := g_DoubleSpaceMs

    if (newTriggerMode = "DoubleSpace") {
        rawDoubleSpaceMs := Trim(g_SettingsLiveDoubleSpaceEdit.Value)
        newDoubleSpaceMs := NormalizeLiveDoubleSpaceMs(rawDoubleSpaceMs, "")

        if (newDoubleSpaceMs = "") {
            Notify("Интервал должен быть числом от 100 до 3000 мс", g_AppName, "Icon!")
            g_SettingsLiveDoubleSpaceEdit.Value := g_DoubleSpaceMs
            return
        }
    }

    oldTriggerMode := g_LiveTriggerMode
    g_LiveTriggerMode := newTriggerMode
    g_DoubleSpaceMs := newDoubleSpaceMs
    g_ShowFirstToggleHint := g_SettingsLiveHintChk.Value = 1

    IniWrite(g_LiveTriggerMode, g_ConfigPath, "General", "LiveTriggerMode")
    IniWrite(String(g_DoubleSpaceMs), g_ConfigPath, "General", "DoubleSpaceMs")
    IniWrite(g_ShowFirstToggleHint ? "1" : "0", g_ConfigPath, "General", "ShowFirstToggleHint")

    if !SetLiveMode(g_SettingsLiveEnabledChk.Value = 1, false, true) {
        g_LiveTriggerMode := oldTriggerMode
        IniWrite(g_LiveTriggerMode, g_ConfigPath, "General", "LiveTriggerMode")
        UpdateLiveConvertHotkeyRegistration()
        SettingsGui_UpdateLiveControls()
        return
    }

    SettingsGui_ShowPage("Live")
    Notify("Live-настройки сохранены", g_AppName, "Iconi")
}


SettingsGui_SetUnicodeControlsVisible(visible) {
    global g_SettingsUnicodeControls

    for _, ctrl in g_SettingsUnicodeControls {
        if IsObject(ctrl) {
            ctrl.Visible := visible
        }
    }
}


SettingsGui_UpdateUnicodeControls() {
    global g_SettingsUnicodeConfirmChk, g_SettingsUnicodeMoveHistoryChk
    global g_SettingsUnicodeHistoryModifierDDL, g_SettingsUnicodeFavoriteModifierDDL
    global g_SettingsUnicodePreviousHistoryModifier, g_SettingsUnicodePreviousFavoriteModifier
    global g_SettingsContentBody

    confirmSelectionWithEnter := UnicodeInput_LoadConfirmSelectionWithEnter()
    moveHistoryOnUse := UnicodeInput_LoadMoveHistoryOnUse()
    historyModifier := UnicodeInput_LoadHistoryShortcutModifier()
    favoriteModifier := UnicodeInput_LoadFavoriteShortcutModifier()
    UnicodeInput_ResolveShortcutModifiers(&historyModifier, &favoriteModifier)

    if IsObject(g_SettingsUnicodeConfirmChk) {
        g_SettingsUnicodeConfirmChk.Value := confirmSelectionWithEnter ? 1 : 0
    }

    if IsObject(g_SettingsUnicodeMoveHistoryChk) {
        g_SettingsUnicodeMoveHistoryChk.Value := moveHistoryOnUse ? 1 : 0
    }

    if IsObject(g_SettingsUnicodeHistoryModifierDDL) {
        g_SettingsUnicodeHistoryModifierDDL.Choose(UnicodeInput_GetModifierIndex(historyModifier))
    }

    if IsObject(g_SettingsUnicodeFavoriteModifierDDL) {
        g_SettingsUnicodeFavoriteModifierDDL.Choose(UnicodeInput_GetModifierIndex(favoriteModifier))
    }

    g_SettingsUnicodePreviousHistoryModifier := historyModifier
    g_SettingsUnicodePreviousFavoriteModifier := favoriteModifier

    if IsObject(g_SettingsContentBody)
        && IsObject(g_SettingsUnicodeConfirmChk)
        && g_SettingsUnicodeConfirmChk.Visible {
        g_SettingsContentBody.Value := SettingsGui_GetUnicodeText()
    }
}


SettingsGui_UnicodeModifierChanged(changedSetting, *) {
    global g_SettingsUnicodeHistoryModifierDDL, g_SettingsUnicodeFavoriteModifierDDL
    global g_SettingsUnicodePreviousHistoryModifier, g_SettingsUnicodePreviousFavoriteModifier

    if (!IsObject(g_SettingsUnicodeHistoryModifierDDL)
     || !IsObject(g_SettingsUnicodeFavoriteModifierDDL)) {
        return
    }

    historyModifier := UnicodeInput_NormalizeShortcutModifier(
        g_SettingsUnicodeHistoryModifierDDL.Text,
        g_SettingsUnicodePreviousHistoryModifier
    )
    favoriteModifier := UnicodeInput_NormalizeShortcutModifier(
        g_SettingsUnicodeFavoriteModifierDDL.Text,
        g_SettingsUnicodePreviousFavoriteModifier
    )

    ; Одно назначение не может управлять двумя списками. Если выбрана уже
    ; занятая клавиша, просто меняем назначения местами.
    if (historyModifier = favoriteModifier) {
        if (changedSetting = "HistoryModifier") {
            favoriteModifier := g_SettingsUnicodePreviousHistoryModifier
            g_SettingsUnicodeFavoriteModifierDDL.Choose(UnicodeInput_GetModifierIndex(favoriteModifier))
        } else {
            historyModifier := g_SettingsUnicodePreviousFavoriteModifier
            g_SettingsUnicodeHistoryModifierDDL.Choose(UnicodeInput_GetModifierIndex(historyModifier))
        }
    }

    g_SettingsUnicodePreviousHistoryModifier := historyModifier
    g_SettingsUnicodePreviousFavoriteModifier := favoriteModifier
}


SettingsGui_SaveUnicodeSettings() {
    global g_SettingsUnicodeConfirmChk, g_SettingsUnicodeMoveHistoryChk
    global g_SettingsUnicodeHistoryModifierDDL, g_SettingsUnicodeFavoriteModifierDDL
    global g_AppName

    if (!IsObject(g_SettingsUnicodeConfirmChk)
     || !IsObject(g_SettingsUnicodeMoveHistoryChk)
     || !IsObject(g_SettingsUnicodeHistoryModifierDDL)
     || !IsObject(g_SettingsUnicodeFavoriteModifierDDL)) {
        return
    }

    historyModifier := UnicodeInput_NormalizeShortcutModifier(g_SettingsUnicodeHistoryModifierDDL.Text, "Ctrl")
    favoriteModifier := UnicodeInput_NormalizeShortcutModifier(g_SettingsUnicodeFavoriteModifierDDL.Text, "Shift")

    if (historyModifier = favoriteModifier) {
        Notify("Для истории и избранного нужны разные клавиши", g_AppName, "Icon!")
        return
    }

    UnicodeInput_SaveConfirmSelectionWithEnter(g_SettingsUnicodeConfirmChk.Value = 1)
    UnicodeInput_SaveMoveHistoryOnUse(g_SettingsUnicodeMoveHistoryChk.Value = 1)

    if !UnicodeInput_SaveShortcutModifiers(historyModifier, favoriteModifier) {
        Notify("Не удалось сохранить настройки быстрого выбора", g_AppName, "Iconx")
        return
    }

    UnicodeInput_RefreshOpenGuiSettings()
    SettingsGui_ShowPage("Unicode")
    Notify("Настройки Unicode Input сохранены", g_AppName, "Iconi")
}


SettingsGui_GetCurrentHotkeyValues() {
    global g_HotkeyLayoutFull, g_HotkeyLayoutMajority, g_HotkeyLiveToggle
    global g_HotkeyLiveConvert, g_HotkeyUnicodeInput, g_HotkeyCapsLockFix
    global g_HotkeyCapsLockFullFix

    return Map(
        "LayoutFull", g_HotkeyLayoutFull,
        "LayoutMajority", g_HotkeyLayoutMajority,
        "LiveToggle", g_HotkeyLiveToggle,
        "LiveConvert", g_HotkeyLiveConvert,
        "UnicodeInput", g_HotkeyUnicodeInput,
        "CapsLockFix", g_HotkeyCapsLockFix,
        "CapsLockFullFix", g_HotkeyCapsLockFullFix
    )
}


SettingsGui_GetHotkeyLabel(actionName) {
    static labels := Map(
        "LayoutFull", "Полное исправление",
        "LayoutMajority", "Исправление по большинству",
        "LiveToggle", "Включить или выключить Live",
        "LiveConvert", "Исправить текущий Live-фрагмент",
        "UnicodeInput", "Unicode Input",
        "CapsLockFix", "CapsLock Fix (умный)",
        "CapsLockFullFix", "CapsLock Full Fix"
    )

    return labels.Has(actionName) ? labels[actionName] : actionName
}


SettingsGui_SetHotkeyControlsVisible(visible) {
    global g_SettingsHotkeyEdits, g_SettingsHotkeyCaptureButtons, g_SettingsHotkeySaveBtn

    for _, editCtrl in g_SettingsHotkeyEdits {
        if IsObject(editCtrl) {
            editCtrl.Visible := visible
        }
    }

    for _, ctrl in g_SettingsHotkeyCaptureButtons {
        if IsObject(ctrl) {
            ctrl.Visible := visible
        }
    }

    if IsObject(g_SettingsHotkeySaveBtn) {
        g_SettingsHotkeySaveBtn.Visible := visible
    }
}


SettingsGui_UpdateHotkeyControls() {
    global g_SettingsHotkeyEdits, g_SettingsPendingHotkeys

    currentValues := SettingsGui_GetCurrentHotkeyValues()
    g_SettingsPendingHotkeys := Map()

    for actionName, editCtrl in g_SettingsHotkeyEdits {
        hotkeyName := currentValues.Has(actionName) ? currentValues[actionName] : ""
        g_SettingsPendingHotkeys[actionName] := hotkeyName
        editCtrl.Value := HotkeyToDisplay(hotkeyName)
    }
}


SettingsGui_IsUnsafeBareHotkey(hotkeyName) {
    if RegExMatch(hotkeyName, "[#!^+]") {
        return false
    }

    keyName := StrLower(GetHotkeyMainKey(hotkeyName))

    if (StrLen(keyName) = 1) {
        return true
    }

    static unsafeKeys := Map(
        "space", true,
        "tab", true,
        "enter", true,
        "esc", true,
        "escape", true,
        "backspace", true,
        "delete", true
    )

    return unsafeKeys.Has(keyName)
}


SettingsGui_SetCapturedModifier(keyName, isDown) {
    global g_HotkeyCaptureModifiers

    switch keyName {
        case "LWin", "RWin":
            g_HotkeyCaptureModifiers["Win"] := isDown
        case "Ctrl", "Control", "LControl", "RControl":
            g_HotkeyCaptureModifiers["Ctrl"] := isDown
        case "Alt", "LAlt", "RAlt":
            g_HotkeyCaptureModifiers["Alt"] := isDown
        case "Shift", "LShift", "RShift":
            g_HotkeyCaptureModifiers["Shift"] := isDown
    }
}


SettingsGui_CaptureKeyDown(captureHook, vk, sc) {
    keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    SettingsGui_SetCapturedModifier(keyName, true)
}


SettingsGui_CaptureKeyUp(captureHook, vk, sc) {
    keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))
    SettingsGui_SetCapturedModifier(keyName, false)
}


SettingsGui_CaptureHotkey(actionName, *) {
    global g_HotkeyCaptureActive, g_LiveBusy
    global g_HotkeyCaptureModifiers
    global g_SettingsHotkeyEdits, g_SettingsPendingHotkeys
    global g_AppName

    if g_HotkeyCaptureActive {
        return
    }

    if g_LiveBusy {
        Notify("Подождите, пока Live-режим закончит исправление текста", g_AppName, "Icon!")
        return
    }

    if !g_SettingsHotkeyEdits.Has(actionName) {
        return
    }

    previousValue := g_SettingsPendingHotkeys.Has(actionName) ? g_SettingsPendingHotkeys[actionName] : ""
    editCtrl := g_SettingsHotkeyEdits[actionName]
    captureHook := ""

    try {
        g_HotkeyCaptureActive := true
        g_HotkeyCaptureModifiers := Map(
            "Win", false,
            "Ctrl", false,
            "Alt", false,
            "Shift", false
        )
        editCtrl.Value := "Нажмите клавиши…"
        ResetTypingBuffer()

        ; Пока окно ждёт новое сочетание, действующие хоткеи не должны
        ; выполнять свои обычные команды.
        Suspend(true)

        captureHook := InputHook("L0 T10")
        captureHook.KeyOpt("{All}", "ESN")
        captureHook.KeyOpt(
            "{LControl}{RControl}{LShift}{RShift}{LAlt}{RAlt}{LWin}{RWin}",
            "-E"
        )
        captureHook.OnKeyDown := SettingsGui_CaptureKeyDown
        captureHook.OnKeyUp := SettingsGui_CaptureKeyUp
        captureHook.Start()
        captureHook.Wait()

        keyName := captureHook.EndKey

        if (keyName = "" || keyName = "Esc" || keyName = "Escape") {
            editCtrl.Value := HotkeyToDisplay(previousValue)
            return
        }

        hotkeyName := ""
        if g_HotkeyCaptureModifiers["Win"] {
            hotkeyName .= "#"
        }
        if g_HotkeyCaptureModifiers["Ctrl"] {
            hotkeyName .= "^"
        }
        if g_HotkeyCaptureModifiers["Alt"] {
            hotkeyName .= "!"
        }
        if g_HotkeyCaptureModifiers["Shift"] {
            hotkeyName .= "+"
        }

        if (StrLen(keyName) = 1) {
            keyName := StrLower(keyName)
        }
        hotkeyName .= keyName

        if SettingsGui_IsUnsafeBareHotkey(hotkeyName) {
            editCtrl.Value := HotkeyToDisplay(previousValue)
            Notify("Добавьте к этой клавише Ctrl, Alt, Shift или Win, чтобы она не мешала обычному набору текста", g_AppName, "Icon!")
            return
        }

        g_SettingsPendingHotkeys[actionName] := hotkeyName
        editCtrl.Value := HotkeyToDisplay(hotkeyName)
    } catch as err {
        editCtrl.Value := HotkeyToDisplay(previousValue)
        Notify("Не удалось распознать сочетание клавиш: " err.Message, g_AppName, "Iconx")
    } finally {
        if IsObject(captureHook) {
            try captureHook.Stop()
        }
        Suspend(false)
        g_HotkeyCaptureActive := false
        ResetTypingBuffer()
    }
}


SettingsGui_NormalizeHotkeyForCompare(hotkeyName) {
    return StrLower(HotkeyToDisplay(Trim(hotkeyName)))
}


SettingsGui_ValidatePendingHotkeys(&message) {
    global g_SettingsPendingHotkeys

    seen := Map()

    for actionName, hotkeyName in g_SettingsPendingHotkeys {
        hotkeyName := Trim(hotkeyName)

        if (hotkeyName = "") {
            message := "Не задано сочетание для функции «" SettingsGui_GetHotkeyLabel(actionName) "»"
            return false
        }

        normalized := SettingsGui_NormalizeHotkeyForCompare(hotkeyName)
        if seen.Has(normalized) {
            message := "Одно сочетание назначено сразу двум функциям: «"
                . SettingsGui_GetHotkeyLabel(seen[normalized]) "» и «"
                . SettingsGui_GetHotkeyLabel(actionName) "»"
            return false
        }

        seen[normalized] := actionName
    }

    message := ""
    return true
}


SettingsGui_SaveCapturedHotkeys(*) {
    global g_SettingsPendingHotkeys, g_HotkeysPath, g_AppName

    if !SettingsGui_ValidatePendingHotkeys(&validationMessage) {
        Notify(validationMessage, g_AppName, "Icon!")
        return
    }

    EnsureHotkeysFile()
    backupPath := g_HotkeysPath ".settings-backup-" A_TickCount
    backupCreated := false

    try {
        FileCopy(g_HotkeysPath, backupPath, true)
        backupCreated := true

        for actionName, hotkeyName in g_SettingsPendingHotkeys {
            IniWrite(Trim(hotkeyName), g_HotkeysPath, "Hotkeys", actionName)
        }

        LoadHotkeys()
        if !RegisterHotkeys() {
            throw Error("Одно или несколько сочетаний не удалось включить")
        }

        SetupTrayMenu()
        SettingsGui_UpdateHotkeyControls()
        SettingsGui_UpdateLiveControls()
        Notify("Горячие клавиши сохранены", g_AppName, "Iconi")
    } catch as err {
        if backupCreated {
            try FileCopy(backupPath, g_HotkeysPath, true)
        }

        LoadHotkeys()
        RegisterHotkeys()
        SetupTrayMenu()
        SettingsGui_UpdateHotkeyControls()
        SettingsGui_UpdateLiveControls()
        Notify("Новые сочетания не сохранены. Предыдущие горячие клавиши восстановлены.`n" err.Message, g_AppName, "Iconx")
    } finally {
        if (backupCreated && FileExist(backupPath)) {
            try FileDelete(backupPath)
        }
    }
}

SettingsGui_GetHotkeysText() {
    text := ""
    text .= "Нажмите «Захватить», затем нужное сочетание. Escape отменяет захват."
    text .= " Дополнительные записи из файла горячих клавиш при сохранении останутся без изменений."

    return text
}


SettingsGui_GetUnicodeText() {
    global g_HotkeyUnicodeInput

    historyModifier := UnicodeInput_LoadHistoryShortcutModifier()
    favoriteModifier := UnicodeInput_LoadFavoriteShortcutModifier()
    UnicodeInput_ResolveShortcutModifiers(&historyModifier, &favoriteModifier)

    text := ""
    text .= "Хоткей: " HotkeyToDisplay(g_HotkeyUnicodeInput) "`r`n"
    text .= "Вводит Unicode-символы по HEX-коду: 2014 → —, 1F600 → 😀.`r`n"
    text .= "Поддерживаются несколько кодов через пробел и слитные 4-значные блоки.`r`n"
    text .= "`r`n"
    text .= "История: " UnicodeInput_GetShortcutDisplay(historyModifier) ". "
    text .= "Избранное: " UnicodeInput_GetShortcutDisplay(favoriteModifier) ".`r`n"
    text .= "Эти настройки синхронизируются с окном Unicode Input.`r`n"
    text .= "Если выбран Tab, обычный переход между полями клавишей Tab в окне Unicode Input отключается.`r`n"

    return text
}


SettingsGui_GetCapsLockText() {
    global g_HotkeyCapsLockFix, g_HotkeyCapsLockFullFix

    text := ""
    text .= "CapsLock Full Fix:`r`n"
    text .= "Хоткей: " HotkeyToDisplay(g_HotkeyCapsLockFullFix) "`r`n"
    text .= "Инвертирует регистр каждой русской и английской буквы без анализа текста.`r`n"
    text .= "Пример: мАМА ПОШЛА В МАГАЗИН → Мама пошла в магазин.`r`n"
    text .= "`r`n"
    text .= "CapsLock Fix (умный):`r`n"
    text .= "Хоткей: " HotkeyToDisplay(g_HotkeyCapsLockFix) "`r`n"
    text .= "Анализирует ошибочный регистр и приводит текст к обычному написанию.`r`n"
    text .= "Пример: эТО пРИМЕР → Это пример.`r`n"
    text .= "`r`n"
    text .= "В обоих режимах слова из словаря исключений сохраняют указанное написание, например GitHub и PowerShell.`r`n"

    return text
}


SettingsGui_GetExclusionsText() {
    global g_ExcludePath, g_ExcludeWords

    text := ""
    text .= "Словарь исключений защищает технические слова, команды, пути и ссылки от нежелательного исправления.`r`n"
    text .= "Он также помогает обоим режимам CapsLock восстановить точное написание слов, например PowerShell.`r`n"
    text .= "`r`n"
    text .= "Ваш словарь:`r`n"
    text .= g_ExcludePath "`r`n"
    text .= "Загружено записей: " g_ExcludeWords.Count "`r`n"
    text .= "`r`n"
    text .= "Добавляйте по одной записи на строку. После сохранения нажмите «Применить изменения».`r`n"
    text .= "Кнопка «Сбросить» заменяет ваш словарь стандартным набором.`r`n"

    return text
}


SettingsGui_GetAboutText() {
    version := SettingsGui_GetVersionFromChangelog()

    text := ""
    text .= "Layout Toolkit`r`n"
    text .= "Версия: " version "`r`n"
    text .= "`r`n"
    text .= "Исправляет текст, набранный в неверной RU/EN-раскладке, приводит в порядок случайный CapsLock и помогает вводить Unicode-символы по HEX-коду.`r`n"
    text .= "`r`n"
    text .= "Работает в фоне и не требует отдельного окна.`r`n"

    return text
}


SettingsGui_GetVersionFromChangelog() {
    changelogPath := A_ScriptDir "\CHANGELOG.md"

    if !FileExist(changelogPath) {
        return "dev"
    }

    try {
        text := FileRead(changelogPath, "UTF-8")
    } catch {
        return "dev"
    }

    for line in StrSplit(text, "`n", "`r") {
        line := Trim(line)

        if RegExMatch(line, "^##\s+\[([^\]]+)\]", &match) {
            return match[1]
        }
    }

    return "dev"
}

SettingsGui_SetActions(label1 := "", action1 := "", label2 := "", action2 := "", label3 := "", action3 := "") {
    global g_SettingsActionBtn1, g_SettingsActionBtn2, g_SettingsActionBtn3
    global g_SettingsAction1, g_SettingsAction2, g_SettingsAction3

    g_SettingsAction1 := action1
    g_SettingsAction2 := action2
    g_SettingsAction3 := action3

    SettingsGui_SetActionButton(g_SettingsActionBtn1, label1)
    SettingsGui_SetActionButton(g_SettingsActionBtn2, label2)
    SettingsGui_SetActionButton(g_SettingsActionBtn3, label3)
}


SettingsGui_SetActionButton(btn, label) {
    if !IsObject(btn) {
        return
    }

    if (label = "") {
        btn.Text := ""
        btn.Visible := false
        return
    }

    btn.Text := label
    btn.Visible := true
}


SettingsGui_ActionButton1(*) {
    global g_SettingsAction1

    SettingsGui_RunAction(g_SettingsAction1)
}


SettingsGui_ActionButton2(*) {
    global g_SettingsAction2

    SettingsGui_RunAction(g_SettingsAction2)
}


SettingsGui_ActionButton3(*) {
    global g_SettingsAction3

    SettingsGui_RunAction(g_SettingsAction3)
}


SettingsGui_RunAction(actionName) {
    switch actionName {
        case "OpenDataDir":
            OpenUserDataDir()

        case "RestartToolkit":
            SettingsGui_RestartToolkit()

        case "SaveLiveSettings":
            SettingsGui_SaveLiveSettings()

        case "SaveUnicodeSettings":
            SettingsGui_SaveUnicodeSettings()
			
        case "OpenUnicodeInputClipboard":
            UnicodeInput("clipboard")

        case "OpenHotkeysFile":
            OpenHotkeysFile()

        case "ReloadHotkeys":
            ReloadHotkeys()
            SettingsGui_ShowPage("Hotkeys")

        case "RestoreDefaultHotkeys":
            RestoreDefaultHotkeys()
            SettingsGui_ShowPage("Hotkeys")

        case "OpenExcludeFile":
            OpenExcludeFile()

        case "ReloadExcludeWords":
            ReloadExcludeWords()
            SettingsGui_ShowPage("Exclusions")

        case "RestoreDefaultExcludeWords":
            RestoreDefaultExcludeWords()
            SettingsGui_ShowPage("Exclusions")

        default:
            return
    }
}

SettingsGui_RestartToolkit(*) {
    global g_AppName

    result := MsgBox(
        "Перезапустить Layout Toolkit?",
        g_AppName,
        "YesNo Icon?"
    )

    if (result != "Yes") {
        return
    }

    try {
        Run('"' A_AhkPath '" "' A_ScriptFullPath '"')
        ExitApp()
    } catch as err {
        Notify("Не удалось перезапустить Layout Toolkit: " err.Message, g_AppName, "Iconx")
    }
}


SettingsGui_OnOff(value) {
    return value ? "включён" : "выключен"
}

SettingsGui_Close(*) {
    global g_SettingsGui

    if IsObject(g_SettingsGui) {
        g_SettingsGui.Hide()
    }
}


SettingsGui_OnClose(guiObj, *) {
    guiObj.Hide()
    return true
}
