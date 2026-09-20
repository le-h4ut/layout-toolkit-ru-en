#Requires AutoHotkey v2.0
#SingleInstance Force
#UseHook

#Include Modules\UnicodeInput.ahk
#Include Modules\CapsLockFix.ahk
#Include Modules\SettingsGui.ahk
#Include Modules\WebSettings.ahk
#Include Modules\WebUnicodeInput.ahk

; ============================================================
; Layout Toolkit RU/EN
;
; Win + F12:
;   выделенный текст -> копировать -> конвертировать весь кусок
;   посимвольно в противоположную раскладку -> вставить обратно.
;
; Win + F11:
;   выделенный смешанный текст -> копировать -> подтянуть
;   чужие токены к языку большинства -> вставить обратно.
;
; Win + F10:
;   включить/выключить live-режим.
;
; Live-режим:
;   двойной пробел или выбранный пользователем хоткей -> текущий
;   набранный фрагмент меняется в противоположную раскладку.
;
; ВАЖНО:
;   live-режим сам нажимает Backspace и Ctrl+V.
;   Для больших документов лучше держать live выключенным.
; ============================================================

Persistent
SendMode "Input"

global g_AppName := "Layout Toolkit"

; Ресурсы программы.
global g_AssetsDir := A_ScriptDir "\Assets"
global g_IconPath := g_AssetsDir "\icon.ico"
global g_DefaultExcludePath := g_AssetsDir "\exclude.default.txt"
global g_DefaultHotkeysPath := g_AssetsDir "\hotkeys.default.ini"

; Новое пользовательское хранилище:
; Documents\Layout Toolkit\
global g_ConfigDir := A_MyDocuments "\Layout Toolkit"
global g_ConfigPath := g_ConfigDir "\settings.ini"
global g_ExcludePath := g_ConfigDir "\exclude.txt"
global g_HotkeysPath := g_ConfigDir "\hotkeys.ini"

; Старые пути нужны только для мягкой миграции.
global g_LegacyConfigDir := A_AppData "\LayoutToolkit"
global g_LegacyConfigPath := g_LegacyConfigDir "\settings.ini"
global g_LegacyExcludePath := A_ScriptDir "\exclude.txt"

global g_ExcludeWords := Map()

; Все хоткеи из Documents\Layout Toolkit\hotkeys.ini.
; Заводские функции используют известные ключи,
; пользовательские модули могут читать свои ключи через GetHotkey().
global g_Hotkeys := Map()

global g_HotkeyLayoutFull := ""
global g_HotkeyLayoutMajority := ""
global g_HotkeyLiveToggle := ""
global g_HotkeyLiveConvert := ""
global g_HotkeyUnicodeInput := ""
global g_HotkeyCapsLockFix := ""
global g_HotkeyCapsLockFullFix := ""

global g_RegisteredHotkeys := []
global g_RegisteredLiveConvertHotkey := ""

EnsureUserDataDir()
MigrateUserData()
EnsureExcludeFile()
LoadExcludeWords()
EnsureHotkeysFile()
LoadHotkeys()

global g_ShowTrayTips := IniRead(g_ConfigPath, "Notifications", "ShowTrayTips", "1") = "1"
global g_PlaySound := IniRead(g_ConfigPath, "Notifications", "PlaySound", "0") = "1"

if FileExist(g_IconPath) {
    TraySetIcon(g_IconPath)
}

global g_LiveEnabled := IniRead(g_ConfigPath, "General", "LiveEnabled", "0") = "1"
global g_LiveTriggerMode := ReadLiveTriggerMode()
global g_DoubleSpaceMs := ReadLiveDoubleSpaceMs()
global g_ShowFirstToggleHint := IniRead(g_ConfigPath, "General", "ShowFirstToggleHint", "1") = "1"
global g_FirstToggleHintShown := IniRead(g_ConfigPath, "General", "FirstToggleHintShown", "0") = "1"

global g_LiveBusy := false
global g_LivePendingBuffer := ""
global g_LiveContextInvalidated := false
global g_LiveOperationWindow := 0
global g_Buffer := ""
global g_Direction := ""          ; "EN_TO_RU" или "RU_TO_EN"
global g_LastSpaceTick := 0

global g_MaxBufferChars := 300
global g_PendingBoundary := false
global g_AfterBoundarySpace := false
global g_BoundaryStart := 0
global g_LiveBoundarySourcePrefix := ""
global g_LiveBoundaryReplacementPrefix := ""
global g_LastWindow := WinExist("A")

EnsureUserDataDir() {
    global g_ConfigDir

    try {
        DirCreate(g_ConfigDir)
    } catch as err {
        MsgBox("Не удалось создать папку настроек:`n" g_ConfigDir "`n`n" err.Message, "Layout Toolkit", "Iconx")
    }
}


MigrateUserData() {
    global g_ConfigPath, g_ExcludePath
    global g_LegacyConfigPath, g_LegacyExcludePath

    ; settings.ini: старый AppData -> новый Documents
    if (!FileExist(g_ConfigPath) && FileExist(g_LegacyConfigPath)) {
        try {
            FileCopy(g_LegacyConfigPath, g_ConfigPath, false)
        }
    }

    ; exclude.txt: старый файл рядом со скриптом -> новый Documents
    if (!FileExist(g_ExcludePath) && FileExist(g_LegacyExcludePath)) {
        try {
            FileCopy(g_LegacyExcludePath, g_ExcludePath, false)
        }
    }
}

EnsureExcludeFile() {
    global g_ExcludePath, g_DefaultExcludePath

    if FileExist(g_ExcludePath) {
        return
    }

    ; Новый нормальный путь:
    ; Assets\exclude.default.txt -> Documents\Layout Toolkit\exclude.txt
    if FileExist(g_DefaultExcludePath) {
        try {
            FileCopy(g_DefaultExcludePath, g_ExcludePath, false)
            return
        }
    }

    ; Fallback, если Assets потеряли или запуск идёт из странной сборки.
    FileAppend(GetDefaultExcludeText(), g_ExcludePath, "UTF-8")
}


GetDefaultExcludeText() {
    defaultText := ""
    defaultText .= "USB`n"
    defaultText .= "AHK`n"
    defaultText .= "PowerShell`n"
    defaultText .= "GitHub`n"
    defaultText .= "CMD`n"
    defaultText .= "Bash`n"
    defaultText .= "Python`n"
    defaultText .= "JavaScript`n"
    defaultText .= "C:\`n"
    defaultText .= "D:\`n"
    defaultText .= "http`n"
    defaultText .= "https`n"
    defaultText .= "www`n"
    defaultText .= ".com`n"
    defaultText .= ".ru`n"

    return defaultText
}


EnsureHotkeysFile() {
    global g_HotkeysPath, g_DefaultHotkeysPath, g_AppName

    if FileExist(g_HotkeysPath) {
        return true
    }

    if FileExist(g_DefaultHotkeysPath) {
        try {
            FileCopy(g_DefaultHotkeysPath, g_HotkeysPath, false)
            return true
        }
    }

    ; Не подменяем отсутствующий заводской файл скрытыми значениями в коде.
    ; Пустой пользовательский файл можно открыть и заполнить вручную.
    try FileAppend("[Hotkeys]`n", g_HotkeysPath, "UTF-8")
    MsgBox(
        "Не найден файл стандартных горячих клавиш:`n" g_DefaultHotkeysPath "`n`nГорячие клавиши программы не будут назначены автоматически.",
        g_AppName,
        "Iconx"
    )
    return false
}


ParseHotkeysFile(path) {
    parsedHotkeys := Map()

    try {
        content := FileRead(path, "UTF-8")
    } catch {
        return parsedHotkeys
    }

    inHotkeysSection := false

    for line in StrSplit(content, "`n", "`r") {
        line := Trim(line)

        ; На случай UTF-8-BOM в начале файла.
        line := StrReplace(line, Chr(0xFEFF), "")

        if (line = "") {
            continue
        }

        ; Комментарии.
        ; Строки вида ИмяДействия=#Сочетание сюда не попадут,
        ; потому что начинаются не с #, а с имени ключа.
        if (SubStr(line, 1, 1) = ";") {
            continue
        }

        if (SubStr(line, 1, 1) = "#") {
            continue
        }

        if (SubStr(line, 1, 1) = "[" && SubStr(line, -1) = "]") {
            sectionName := SubStr(line, 2, StrLen(line) - 2)
            inHotkeysSection := sectionName = "Hotkeys"
            continue
        }

        if !inHotkeysSection {
            continue
        }

        eqPos := InStr(line, "=")

        if (eqPos <= 1) {
            continue
        }

        key := Trim(SubStr(line, 1, eqPos - 1))
        value := Trim(SubStr(line, eqPos + 1))

        if (key = "" || value = "") {
            continue
        }

        parsedHotkeys[key] := value
    }

    return parsedHotkeys
}


LoadHotkeys(*) {
    global g_HotkeysPath, g_DefaultHotkeysPath, g_Hotkeys
    global g_HotkeyLayoutFull, g_HotkeyLayoutMajority, g_HotkeyLiveToggle
    global g_HotkeyLiveConvert, g_HotkeyUnicodeInput, g_HotkeyCapsLockFix
    global g_HotkeyCapsLockFullFix

    EnsureHotkeysFile()

    ; Assets\hotkeys.default.ini — единственный источник заводских значений.
    ; Пользовательский hotkeys.ini накладывается поверх него и может добавлять
    ; собственные ключи для дополнительных модулей.
    defaultHotkeys := ParseHotkeysFile(g_DefaultHotkeysPath)
    mergedHotkeys := Map()
    userHotkeys := ParseHotkeysFile(g_HotkeysPath)

    for key, value in defaultHotkeys {
        mergedHotkeys[key] := value
    }

    ; До появления полного режима заводской CapsLock Fix использовал F12.
    ; Если пользовательский файл всё ещё содержит именно эту старую схему,
    ; берём новое заводское значение F11 для умного режима. Пользовательские
    ; сочетания с другими значениями остаются без изменений.
    legacyCapsLockDefaults := !userHotkeys.Has("CapsLockFullFix")
        && userHotkeys.Has("CapsLockFix")
        && StrLower(Trim(userHotkeys["CapsLockFix"])) = "#+f12"

    for key, value in userHotkeys {
        mergedHotkeys[key] := value
    }

    if (legacyCapsLockDefaults && defaultHotkeys.Has("CapsLockFix")) {
        mergedHotkeys["CapsLockFix"] := defaultHotkeys["CapsLockFix"]
    }

    g_Hotkeys := mergedHotkeys

    ; Заводские хоткеи LT.
    g_HotkeyLayoutFull := GetHotkey("LayoutFull")
    g_HotkeyLayoutMajority := GetHotkey("LayoutMajority")
    g_HotkeyLiveToggle := GetHotkey("LiveToggle")
    g_HotkeyLiveConvert := GetHotkey("LiveConvert")
    g_HotkeyUnicodeInput := GetHotkey("UnicodeInput")
    g_HotkeyCapsLockFix := GetHotkey("CapsLockFix")
    g_HotkeyCapsLockFullFix := GetHotkey("CapsLockFullFix")
}

GetHotkey(actionName, defaultValue := "") {
    global g_Hotkeys

    actionName := Trim(actionName)

    if (actionName = "") {
        return defaultValue
    }

    if g_Hotkeys.Has(actionName) {
        return g_Hotkeys[actionName]
    }

    return defaultValue
}


LoadExcludeWords(*) {
    global g_ExcludePath, g_ExcludeWords

    g_ExcludeWords := Map()
    EnsureExcludeFile()

    try {
        content := FileRead(g_ExcludePath, "UTF-8")
    } catch {
        return
    }

    for line in StrSplit(content, "`n", "`r") {
        word := Trim(line)

        if (word = "") {
            continue
        }

        if (SubStr(word, 1, 1) = "#") {
            continue
        }

        g_ExcludeWords[StrLower(word)] := word
    }
}


SplitByWhitespace(text) {
    parts := []
    pos := 1

    while pos := RegExMatch(text, "\s+|\S+", &match, pos) {
        parts.Push(match[0])
        pos += StrLen(match[0])
    }

    return parts
}

GetCanonicalExcludedToken(token) {
    global g_ExcludeWords

    trimChars := " `t`r`n'()[]{}<>.,;:!?" . Chr(34)

    raw := Trim(token)
    cleaned := Trim(token, trimChars)

    rawKey := StrLower(raw)
    cleanedKey := StrLower(cleaned)

    ; Полное совпадение без обрезки пунктуации.
    if (rawKey != "" && g_ExcludeWords.Has(rawKey)) {
        return g_ExcludeWords[rawKey]
    }

    ; Совпадение с обрезкой пунктуации по краям.
    if (cleanedKey != "" && g_ExcludeWords.Has(cleanedKey)) {
        canonical := g_ExcludeWords[cleanedKey]

        startPos := InStr(token, cleaned)

        if (startPos > 0) {
            prefix := SubStr(token, 1, startPos - 1)
            suffix := SubStr(token, startPos + StrLen(cleaned))
            return prefix canonical suffix
        }

        return canonical
    }

    return ""
}


IsExcludedToken(token) {
    global g_ExcludeWords

    trimChars := " `t`r`n'()[]{}<>.,;:!?" . Chr(34)

    raw := StrLower(Trim(token))
    cleaned := StrLower(Trim(token, trimChars))

    candidates := [raw, cleaned]

    for _, candidate in candidates {
        if (candidate = "") {
            continue
        }

        ; Точное совпадение: USB, PowerShell, GitHub и т.д.
        if g_ExcludeWords.Has(candidate) {
            return true
        }

        ; Windows-пути: C:\Windows, D:\Games и т.д.
        if (StrLen(candidate) >= 3) {
            drivePrefix := SubStr(candidate, 1, 3)

            if (SubStr(drivePrefix, 2, 2) = ":\") {
                if g_ExcludeWords.Has(drivePrefix) {
                    return true
                }
            }
        }

        ; URL
        if g_ExcludeWords.Has("http") {
            if (SubStr(candidate, 1, 7) = "http://") {
                return true
            }
        }

        if g_ExcludeWords.Has("https") {
            if (SubStr(candidate, 1, 8) = "https://") {
                return true
            }
        }

        if g_ExcludeWords.Has("www") {
            if (SubStr(candidate, 1, 4) = "www.") {
                return true
            }
        }

        ; Доменные хвосты: github.com, site.ru
        for item, _ in g_ExcludeWords {
            if (SubStr(item, 1, 1) = ".") {
                if (StrLen(candidate) >= StrLen(item)) {
                    tail := SubStr(candidate, StrLen(candidate) - StrLen(item) + 1)

                    if (tail = item) {
                        return true
                    }
                }
            }
        }
    }

    return false
}


CountLayoutLetters(text, &latin, &cyrillic) {
    latin := 0
    cyrillic := 0

    for part in SplitByWhitespace(text) {
        if part ~= "^\s+$" {
            continue
        }

        if IsExcludedToken(part) {
            continue
        }

        for ch in StrSplit(part) {
            if IsLatin(ch) {
                latin++
            } else if IsCyrillic(ch) {
                cyrillic++
            }
        }
    }
}


SetupTrayMenu()

; Глобальный перехват ввода.
; L0 не даёт InputHook остановиться после стандартного лимита в 1023 символа.
; I1 отсекает искусственный ввод самого AHK, не затрагивая физические клавиши.
ih := InputHook("V L0 I1")
ih.OnChar := IH_OnChar
ih.OnKeyDown := IH_OnKeyDown
ih.NotifyNonText := true
if g_LiveEnabled {
    ih.Start()
}

firstRunDone := IniRead(g_ConfigPath, "General", "FirstRunDone", "0")
if (firstRunDone != "1") {
    ShowTrainingGui(true)
} else {
    Notify("Запущено. Live: " (g_LiveEnabled ? "включён" : "выключен"), g_AppName, "Iconi")
}

; Горячие клавиши читаются из Documents\Layout Toolkit\hotkeys.ini.
; Важно: RegisterHotkeys() должен быть ДО первых статических hotkey-строк.
RegisterHotkeys()
; Unicode Input is used frequently: prepare its hidden WebView shortly after
; startup, then reuse it instead of paying the browser startup cost per call.
SetTimer(ObjBindMethod(LTWebUnicodeInput, "Prewarm"), -1500)
OnExit((*) => LTWebUnicodeInput.Dispose())

; Сброс буфера при клике мышью.
~LButton::HandleLiveContextBreak()
~RButton::HandleLiveContextBreak()
~MButton::HandleLiveContextBreak()

; Пробел ловим сами, чтобы второй пробел был командой, а не обычным вводом.
#MaxThreadsPerHotkey 2
#HotIf g_LiveEnabled && g_LiveTriggerMode = "DoubleSpace" && !g_HotkeyCaptureActive
$*Space::LiveSpacePressed()
#HotIf
#MaxThreadsPerHotkey 1

RegisterHotkeys() {
    global g_HotkeyLayoutFull, g_HotkeyLayoutMajority, g_HotkeyLiveToggle
    global g_HotkeyUnicodeInput, g_HotkeyCapsLockFix, g_HotkeyCapsLockFullFix
    global g_RegisteredHotkeys

    DisableRegisteredLiveConvertHotkey()

    ; Если потом будем перезагружать хоткеи без полного рестарта,
    ; сначала отключаем ранее зарегистрированные.
    for _, hotkeyName in g_RegisteredHotkeys {
        try {
            Hotkey(hotkeyName, "Off")
        }
    }

    g_RegisteredHotkeys := []

    success := true

    if !RegisterOneHotkey(g_HotkeyLayoutFull, (*) => ConvertSelectedFullHotkey(), "Layout full fix") {
        success := false
    }
    if !RegisterOneHotkey(g_HotkeyLayoutMajority, (*) => ConvertSelectedMajorityHotkey(), "Layout majority fix") {
        success := false
    }
    if !RegisterOneHotkey(g_HotkeyLiveToggle, (*) => ToggleLiveMode(), "Live toggle") {
        success := false
    }
    if !RegisterOneHotkey(g_HotkeyUnicodeInput, (*) => UnicodeInput("insert"), "Unicode Input") {
        success := false
    }
    if !RegisterOneHotkey(g_HotkeyCapsLockFix, (*) => CapsLockFixSelectedHotkey(), "CapsLock Fix") {
        success := false
    }
    if !RegisterOneHotkey(g_HotkeyCapsLockFullFix, (*) => CapsLockFullFixSelectedHotkey(), "CapsLock Full Fix") {
        success := false
    }
    if !UpdateLiveConvertHotkeyRegistration() {
        success := false
    }

    return success
}


RegisterOneHotkey(hotkeyName, action, displayName := "") {
    global g_RegisteredHotkeys, g_AppName

    hotkeyName := Trim(hotkeyName)

    if (hotkeyName = "") {
        return true
    }

    try {
        Hotkey(hotkeyName, action, "On")
        g_RegisteredHotkeys.Push(hotkeyName)
        return true
    } catch as err {
        if (displayName = "") {
            displayName := hotkeyName
        }

        Notify("Не удалось зарегистрировать хоткей " displayName ": " hotkeyName "`n" err.Message, g_AppName, "Iconx")
        return false
    }
}


DisableRegisteredLiveConvertHotkey() {
    global g_RegisteredLiveConvertHotkey

    if (g_RegisteredLiveConvertHotkey != "") {
        try Hotkey(g_RegisteredLiveConvertHotkey, "Off")
        g_RegisteredLiveConvertHotkey := ""
    }
}


UpdateLiveConvertHotkeyRegistration() {
    global g_LiveEnabled, g_LiveTriggerMode
    global g_HotkeyLiveConvert, g_RegisteredLiveConvertHotkey
    global g_HotkeyLayoutFull, g_HotkeyLayoutMajority, g_HotkeyLiveToggle
    global g_HotkeyUnicodeInput, g_HotkeyCapsLockFix, g_HotkeyCapsLockFullFix, g_AppName

    DisableRegisteredLiveConvertHotkey()

    if (!g_LiveEnabled || g_LiveTriggerMode != "Hotkey" || Trim(g_HotkeyLiveConvert) = "") {
        return true
    }

    liveKey := StrLower(HotkeyToDisplay(g_HotkeyLiveConvert))
    occupied := [
        g_HotkeyLayoutFull,
        g_HotkeyLayoutMajority,
        g_HotkeyLiveToggle,
        g_HotkeyUnicodeInput,
        g_HotkeyCapsLockFix,
        g_HotkeyCapsLockFullFix
    ]

    for _, hotkeyName in occupied {
        if (liveKey = StrLower(HotkeyToDisplay(hotkeyName))) {
            Notify("Хоткей Live-конвертации совпадает с другой функцией: " HotkeyToDisplay(g_HotkeyLiveConvert), g_AppName, "Icon!")
            return false
        }
    }

    try {
        Hotkey(g_HotkeyLiveConvert, LiveConvertHotkeyPressed, "On")
        g_RegisteredLiveConvertHotkey := g_HotkeyLiveConvert
        return true
    } catch as err {
        Notify("Не удалось зарегистрировать хоткей Live-конвертации: " g_HotkeyLiveConvert "`n" err.Message, g_AppName, "Iconx")
        return false
    }
}


HotkeyToDisplay(hotkeyName) {
    hotkeyName := Trim(hotkeyName)

    if (hotkeyName = "") {
        return "не задан"
    }

    result := ""

    if InStr(hotkeyName, "#") {
        result .= "Win+"
    }

    if InStr(hotkeyName, "^") {
        result .= "Ctrl+"
    }

    if InStr(hotkeyName, "+") {
        result .= "Shift+"
    }

    if InStr(hotkeyName, "!") {
        result .= "Alt+"
    }

    key := hotkeyName
    key := StrReplace(key, "#", "")
    key := StrReplace(key, "^", "")
    key := StrReplace(key, "+", "")
    key := StrReplace(key, "!", "")

    ; Красиво выводим одиночные буквы.
    if (StrLen(key) = 1) {
        key := StrUpper(key)
    }

    return result key
}

SetupTrayMenu() {
    global g_AppName, g_ShowTrayTips, g_PlaySound, g_LiveEnabled
    global g_HotkeyLiveToggle

    A_TrayMenu.Delete()

    A_TrayMenu.Add("Краткая справка", (*) => ShowTrainingGui(false))
    A_TrayMenu.Add("Настройки...", OpenSettingsGui)
    A_TrayMenu.Add("Открыть папку данных", OpenUserDataDir)
    A_TrayMenu.Add("Открыть словарь исключений", OpenExcludeFile)
    A_TrayMenu.Add("Применить изменения словаря", ReloadExcludeWords)
    A_TrayMenu.Add()

    A_TrayMenu.Add("Показывать уведомления", ToggleTrayTips)
    A_TrayMenu.Add("Звук уведомлений", ToggleNotificationSound)

    if g_ShowTrayTips {
        A_TrayMenu.Check("Показывать уведомления")
    } else {
        A_TrayMenu.Uncheck("Показывать уведомления")
    }

    if g_PlaySound {
        A_TrayMenu.Check("Звук уведомлений")
    } else {
        A_TrayMenu.Uncheck("Звук уведомлений")
    }

    A_TrayMenu.Add()
    
	liveLabel := "Live-режим  " HotkeyToDisplay(g_HotkeyLiveToggle)
    A_TrayMenu.Add(liveLabel, ToggleLiveMode)
    
    if g_LiveEnabled {
        A_TrayMenu.Check(liveLabel)
    } else {
        A_TrayMenu.Uncheck(liveLabel)
    }

    A_TrayMenu.Add()
    A_TrayMenu.Add("Выход", (*) => ExitApp())

    ; Двойной клик по иконке в трее открывает настройки.
    ; Правый клик по-прежнему показывает обычное меню.
    A_TrayMenu.Default := "Настройки..."
    A_TrayMenu.ClickCount := 2

    A_IconTip := g_AppName
}

Notify(message, title := "", options := "Iconi", playSound := false) {
    global g_AppName, g_ShowTrayTips, g_PlaySound

    if (title = "") {
        title := g_AppName
    }

    if !g_ShowTrayTips {
        return
    }

    finalOptions := options

    if !g_PlaySound {
        finalOptions := finalOptions " Mute"
    }

    TrayTip(message, title, finalOptions)
}

OpenUserDataDir(*) {
    global g_ConfigDir

    EnsureUserDataDir()

    try {
        Run('explorer.exe "' g_ConfigDir '"')
    } catch as err {
        Notify("Не удалось открыть папку данных: " err.Message, "Layout Toolkit", "Iconx")
    }
}

OpenExcludeFile(*) {
    global g_ExcludePath

    EnsureExcludeFile()

    try {
        Run('notepad.exe "' g_ExcludePath '"')
    } catch as err {
        Notify("Не удалось открыть словарь исключений: " err.Message, "Layout Toolkit", "Iconx")
    }
}

ReloadExcludeWords(*) {
    global g_AppName, g_ExcludeWords

    LoadExcludeWords()
    Notify("Словарь исключений перезагружен. Записей: " g_ExcludeWords.Count, g_AppName, "Iconi")
}

RestoreDefaultExcludeWords(*) {
    global g_AppName, g_ExcludePath, g_DefaultExcludePath, g_ExcludeWords

    result := MsgBox(
        "Сбросить словарь исключений?`n`nВаши записи будут заменены стандартным набором.",
        g_AppName,
        "YesNo Icon?"
    )

    if (result != "Yes") {
        return
    }

    try {
        EnsureUserDataDir()

        if FileExist(g_DefaultExcludePath) {
            FileCopy(g_DefaultExcludePath, g_ExcludePath, true)
        } else {
            if FileExist(g_ExcludePath) {
                FileDelete(g_ExcludePath)
            }

            FileAppend(GetDefaultExcludeText(), g_ExcludePath, "UTF-8")
        }

        LoadExcludeWords()

        Notify("Словарь исключений сброшен до стандартного. Записей: " g_ExcludeWords.Count, g_AppName, "Iconi")
    } catch as err {
        Notify("Не удалось сбросить словарь исключений: " err.Message, g_AppName, "Iconx")
    }
}

OpenHotkeysFile(*) {
    global g_HotkeysPath, g_AppName

    EnsureHotkeysFile()

    try {
        Run('notepad.exe "' g_HotkeysPath '"')
    } catch as err {
        Notify("Не удалось открыть файл горячих клавиш: " err.Message, g_AppName, "Iconx")
    }
}


ReloadHotkeys(*) {
    global g_AppName, g_Hotkeys

    LoadHotkeys()
    RegisterHotkeys()
    SetupTrayMenu()

    Notify("Горячие клавиши перезагружены. Записей: " g_Hotkeys.Count, g_AppName, "Iconi")
}


RestoreDefaultHotkeys(*) {
    global g_AppName, g_HotkeysPath, g_DefaultHotkeysPath

    result := MsgBox(
        "Сбросить горячие клавиши?`n`nВаши сочетания будут заменены стандартными.",
        g_AppName,
        "YesNo Icon?"
    )

    if (result != "Yes") {
        return
    }

    try {
        EnsureUserDataDir()

        if !FileExist(g_DefaultHotkeysPath) {
            Notify("Не найден файл стандартных горячих клавиш. Текущие настройки сохранены без изменений", g_AppName, "Icon!")
            return
        }

        FileCopy(g_DefaultHotkeysPath, g_HotkeysPath, true)

        LoadHotkeys()
        RegisterHotkeys()
        SetupTrayMenu()

        Notify("Горячие клавиши сброшены до стандартных.", g_AppName, "Iconi")
    } catch as err {
        Notify("Не удалось сбросить горячие клавиши: " err.Message, g_AppName, "Iconx")
    }
}

ToggleTrayTips(*) {
    global g_ShowTrayTips, g_ConfigPath, g_AppName

    g_ShowTrayTips := !g_ShowTrayTips
    IniWrite(g_ShowTrayTips ? "1" : "0", g_ConfigPath, "Notifications", "ShowTrayTips")

    SetupTrayMenu()

    if g_ShowTrayTips {
        Notify("Уведомления включены", g_AppName, "Iconi")
    }
}


ToggleNotificationSound(*) {
    global g_PlaySound, g_ConfigPath, g_AppName

    g_PlaySound := !g_PlaySound
    IniWrite(g_PlaySound ? "1" : "0", g_ConfigPath, "Notifications", "PlaySound")

    SetupTrayMenu()

    Notify(g_PlaySound ? "Звук уведомлений включён" : "Звук уведомлений выключен", g_AppName, "Iconi", g_PlaySound)
}


NormalizeLiveTriggerMode(value) {
    return StrLower(Trim(value)) = "hotkey" ? "Hotkey" : "DoubleSpace"
}


ReadLiveTriggerMode() {
    global g_ConfigPath

    value := IniRead(g_ConfigPath, "General", "LiveTriggerMode", "DoubleSpace")
    return NormalizeLiveTriggerMode(value)
}


NormalizeLiveDoubleSpaceMs(value, fallback := 700) {
    value := Trim(value)

    if !RegExMatch(value, "^\d+$") {
        return fallback
    }

    ms := Integer(value)

    if (ms < 100 || ms > 3000) {
        return fallback
    }

    return ms
}


ReadLiveDoubleSpaceMs() {
    global g_ConfigPath

    value := IniRead(g_ConfigPath, "General", "DoubleSpaceMs", "700")
    return NormalizeLiveDoubleSpaceMs(value, 700)
}


ShowLiveFirstToggleHint() {
    global g_AppName, g_ConfigPath
    global g_ShowFirstToggleHint, g_FirstToggleHintShown
    global g_LiveTriggerMode, g_HotkeyLiveConvert

    if (!g_ShowFirstToggleHint || g_FirstToggleHintShown) {
        return
    }

    g_FirstToggleHintShown := true
    IniWrite("1", g_ConfigPath, "General", "FirstToggleHintShown")

    selectedMode := g_LiveTriggerMode = "Hotkey"
        ? "Сейчас выбран запуск по горячей клавише: " HotkeyToDisplay(g_HotkeyLiveConvert) "."
        : "Сейчас выбран запуск по двойному пробелу."

    MsgBox(
        "Live-режим включён.`n`n"
        . selectedMode "`n`n"
        . "Двойной пробел исправляет текущий фрагмент и оставляет после него один пробел.`n"
        . "Горячая клавиша исправляет текущий фрагмент и ничего не добавляет в конец.`n`n"
        . "Это два альтернативных способа запуска; выбрать активный можно в настройках.`n"
        . "Если режим мешает в игре или приложении, выключите его горячей клавишей или через меню в трее.`n`n"
        . "Эту подсказку можно отключить в настройках.",
        g_AppName " — Live-режим",
        "Iconi"
    )
}

ShowTrainingGui(isFirstRun := false) {
    global g_LiveEnabled, g_AppName
    global g_HotkeyLayoutFull, g_HotkeyLayoutMajority, g_HotkeyLiveToggle
    global g_HotkeyLiveConvert, g_HotkeyUnicodeInput, g_HotkeyCapsLockFix
    global g_HotkeyCapsLockFullFix

    guiObj := Gui("+AlwaysOnTop", g_AppName " — краткая справка")
    guiObj.SetFont("s10", "Segoe UI")

    guiObj.SetFont("s12 bold", "Segoe UI")
    guiObj.AddText("x20 y16 w600 h26", "Layout Toolkit — исправление текста и ввод Unicode")

    guiObj.SetFont("s9 norm", "Segoe UI")
    guiObj.AddText("x20 y45 w600 h36", "Программа работает в фоне. Основные функции доступны через горячие клавиши, меню в трее и настройки.")
    
    body := ""
    body .= "1. Исправление раскладки`r`n"
    body .= "Сначала выделите текст.`r`n"
    body .= "Полное исправление: " HotkeyToDisplay(g_HotkeyLayoutFull) " — определяет направление отдельно для каждого слова и меняет символы по раскладке.`r`n"
    body .= "Слова из словаря исключений остаются без изменений.`r`n"
    body .= "По большинству: " HotkeyToDisplay(g_HotkeyLayoutMajority) " — подходит для смешанного текста.`r`n"
    body .= "`r`n"

    body .= "2. Live-режим`r`n"
    body .= "Переключение: " HotkeyToDisplay(g_HotkeyLiveToggle) ".`r`n"
    body .= "Двойной пробел исправляет текущий фрагмент и оставляет один пробел в конце.`r`n"
    body .= "Альтернативный запуск по хоткею: " HotkeyToDisplay(g_HotkeyLiveConvert) ". Он ничего не добавляет в конец.`r`n"
    body .= "В настройках выбирается только один активный способ запуска.`r`n"
    body .= "`r`n"

    body .= "3. Unicode Input`r`n"
    body .= "Хоткей: " HotkeyToDisplay(g_HotkeyUnicodeInput) ".`r`n"
    body .= "Введите HEX-код, например 2014 → — или 1F600 → 😀.`r`n"
    body .= "В окне доступны недавние символы и избранные последовательности.`r`n"
    body .= "Из настроек Unicode Input можно открыть в режиме копирования.`r`n"
    body .= "`r`n"

    body .= "4. Исправление CapsLock`r`n"
    body .= "Полный режим: " HotkeyToDisplay(g_HotkeyCapsLockFullFix) " — инвертирует регистр каждой буквы.`r`n"
    body .= "Умный режим: " HotkeyToDisplay(g_HotkeyCapsLockFix) " — приводит ошибочный регистр к обычному написанию.`r`n"
    body .= "Словарь исключений сохраняет точное написание слов, например PowerShell и GitHub.`r`n"
    body .= "`r`n"

    body .= "5. Настройки`r`n"
    body .= "Двойной щелчок по значку Layout Toolkit в трее открывает настройки.`r`n"
    body .= "Там можно управлять Live-режимом, горячими клавишами и словарём исключений.`r`n"
    body .= "`r`n"

    body .= "Для больших фрагментов используйте Layout Fix по выделению; Live-режим рассчитан на короткий текст во время набора."

    guiObj.SetFont("s9 norm", "Segoe UI")
    bodyEdit := guiObj.AddEdit("x20 y90 w600 h300 ReadOnly +Wrap VScroll -Tabstop", body)

    chk := guiObj.AddCheckbox("vStartLive x20 y405 w600 h24", "Включить Live-режим")
    chk.Value := g_LiveEnabled ? 1 : 0

    primaryLabel := isFirstRun ? "Сохранить и больше не показывать" : "Сохранить"
    closeLabel := isFirstRun ? "Закрыть без сохранения" : "Закрыть"
    btnOk := guiObj.AddButton("Default x20 y445 w245 h32", primaryLabel)
    btnSettings := guiObj.AddButton("x280 y445 w165 h32", "Открыть настройки")
    btnCloseOnly := guiObj.AddButton("x460 y445 w160 h32", closeLabel)

    btnOk.OnEvent("Click", (*) => TrainingGuiOk(guiObj))
    btnSettings.OnEvent("Click", (*) => OpenSettingsGui())
    btnCloseOnly.OnEvent("Click", (*) => TrainingGuiCloseOnlyNow(guiObj, isFirstRun))

    guiObj.OnEvent("Close", (*) => TrainingGuiCloseOnlyNow(guiObj, isFirstRun))

    guiObj.Show("w640 h500")
    btnOk.Focus()
}


TrainingGuiOk(guiObj) {
    global g_LiveEnabled, g_ConfigPath, g_AppName

    data := guiObj.Submit(false)

    desiredLive := data.StartLive = 1

    IniWrite("1", g_ConfigPath, "General", "FirstRunDone")
    SetLiveMode(desiredLive, false, false)

    guiObj.Destroy()

    Notify("Готово. Live: " (g_LiveEnabled ? "включён" : "выключен"), g_AppName, "Iconi")
}

TrainingGuiCloseOnlyNow(guiObj, isFirstRun := false) {
    global g_ConfigPath

    if isFirstRun {
        IniWrite("0", g_ConfigPath, "General", "FirstRunDone")
    }

    guiObj.Destroy()
}

SetLiveMode(enabled, showNotify := true, showFirstHint := true) {
    global g_LiveEnabled, g_ConfigPath, g_AppName, ih

    enabled := enabled ? true : false
    oldEnabled := g_LiveEnabled
    stateChanged := g_LiveEnabled != enabled

    g_LiveEnabled := enabled
    IniWrite(g_LiveEnabled ? "1" : "0", g_ConfigPath, "General", "LiveEnabled")

    ResetTypingBuffer()

    if stateChanged {
        try {
            if g_LiveEnabled {
                ih.Start()
            } else {
                ih.Stop()
            }
        } catch as err {
            g_LiveEnabled := oldEnabled
            IniWrite(g_LiveEnabled ? "1" : "0", g_ConfigPath, "General", "LiveEnabled")
            try {
                if g_LiveEnabled {
                    ih.Start()
                } else {
                    ih.Stop()
                }
            }
            SetupTrayMenu()
            Notify("Не удалось переключить Live-режим: " err.Message, g_AppName, "Icon!")
            return false
        }

        SetupTrayMenu()
    }

    if !UpdateLiveConvertHotkeyRegistration() {
        if stateChanged {
            g_LiveEnabled := oldEnabled
            IniWrite(g_LiveEnabled ? "1" : "0", g_ConfigPath, "General", "LiveEnabled")
            try {
                if g_LiveEnabled {
                    ih.Start()
                } else {
                    ih.Stop()
                }
            }
            UpdateLiveConvertHotkeyRegistration()
            SetupTrayMenu()
        }
        return false
    }

    if (g_LiveEnabled && stateChanged && showFirstHint) {
        ShowLiveFirstToggleHint()
    }

    if showNotify {
        Notify(
            g_LiveEnabled ? "Live-режим включён" : "Live-режим выключен",
            g_AppName,
            g_LiveEnabled ? "Iconi" : "Icon!"
        )
    }

    return true
}


ToggleLiveMode(*) {
    global g_LiveEnabled

    SetLiveMode(!g_LiveEnabled, true, true)
}


; ============================================================
; Win + F12: токенная RU ↔ EN-конвертация всего выделения
; ============================================================

ConvertSelectedFullHotkey() {
    global g_AppName

    title := g_AppName " — Полное исправление"
    oldClipboard := ClipboardAll()

    A_Clipboard := ""
    Send "^c"

    if !ClipWait(1.0) {
        A_Clipboard := oldClipboard
        Notify("Не удалось получить выделенный текст", title, "Icon!")
        return
    }

    text := A_Clipboard

    if (text = "") {
        A_Clipboard := oldClipboard
        Notify("Выделенный текст пуст", title, "Icon!")
        return
    }

    result := ConvertFullText(text)

    if (result = text) {
        A_Clipboard := oldClipboard
        Notify("Не удалось определить раскладку или исправлять нечего", title, "Iconi")
        return
    }

    try {
        A_Clipboard := ""
	Sleep 30
	A_Clipboard := result
	
	if !ClipWait(0.5) {
		A_Clipboard := oldClipboard
		Notify("Не удалось подготовить исправленный текст. Буфер обмена восстановлен", title, "Icon!")
		return
	}
	
	Sleep 150
	Send "^v"
	
	Sleep 500
	A_Clipboard := oldClipboard

        Notify("Текст исправлен", title, "Iconi", true)
    } catch as err {
        try {
            A_Clipboard := oldClipboard
        }
        Notify("Не удалось вставить исправленный текст: " err.Message, title, "Iconx")
    }
}


ConvertFullText(text) {
    out := ""

    for part in SplitByWhitespace(text) {
        if IsExcludedToken(part) {
            out .= part
            continue
        }

        out .= ConvertFullToken(part)
    }

    return out
}


ConvertFullToken(token) {
    latin := 0
    cyrillic := 0

    for ch in StrSplit(token) {
        if IsLatin(ch) {
            latin++
        } else if IsCyrillic(ch) {
            cyrillic++
        }
    }

    if (latin > 0 && cyrillic = 0) {
        return ConvertFullTokenByDirection(token, "EN_TO_RU")
    }

    if (cyrillic > 0 && latin = 0) {
        return ConvertFullTokenByDirection(token, "RU_TO_EN")
    }

    ; Для токена без букв или со смешанными алфавитами сохраняем прежнюю
    ; побуквенную логику. Неоднозначные знаки в нём не конвертируем.
    enToRu := GetConversionTable("EN_TO_RU")
    ruToEn := GetConversionTable("RU_TO_EN")
    out := ""

    for ch in StrSplit(token) {
        if IsLatin(ch) {
            out .= enToRu.Has(ch) ? enToRu[ch] : ch
        } else if IsCyrillic(ch) {
            out .= ruToEn.Has(ch) ? ruToEn[ch] : ch
        } else {
            out .= ch
        }
    }

    return out
}


ConvertFullTokenByDirection(token, direction) {
    table := GetConversionTable(direction)
    out := ""

    for ch in StrSplit(token) {
        out .= table.Has(ch) ? table[ch] : ch
    }

    return out
}


; ============================================================
; Win + F11: смешанный текст подтянуть к языку большинства
; ============================================================

ConvertSelectedMajorityHotkey() {
    global g_AppName

    title := g_AppName " — Исправление по большинству"
    oldClipboard := ClipboardAll()

    A_Clipboard := ""
    Send "^c"

    if !ClipWait(1.0) {
        A_Clipboard := oldClipboard
        Notify("Не удалось получить выделенный текст", title, "Icon!")
        return
    }

    text := A_Clipboard

    if (text = "") {
        A_Clipboard := oldClipboard
        Notify("Выделенный текст пуст", title, "Icon!")
        return
    }

    result := ConvertToMajority(text)

    if (result = text) {
        A_Clipboard := oldClipboard
        Notify("В выделенном тексте нечего исправлять", title, "Iconi")
        return
    }

    try {
    A_Clipboard := ""
	Sleep 30
	A_Clipboard := result
	
	if !ClipWait(0.5) {
		A_Clipboard := oldClipboard
		Notify("Не удалось подготовить исправленный текст. Буфер обмена восстановлен", title, "Icon!")
		return
	}

	Sleep 150
	Send "^v"

	Sleep 500
	A_Clipboard := oldClipboard

        Notify("Текст исправлен", title, "Iconi", true)
    } catch as err {
        try {
            A_Clipboard := oldClipboard
        }
        Notify("Не удалось вставить исправленный текст: " err.Message, title, "Iconx")
    }
}


ConvertToMajority(text) {
    CountLayoutLetters(text, &latin, &cyrillic)

    if ((latin = 0 && cyrillic = 0) || latin = cyrillic) {
        return text
    }

    if (latin > cyrillic) {
        ; Английского больше: чиним только русские токены в EN.
        table := GetConversionTable("RU_TO_EN")
        minorityCheck := IsCyrillic
        majorityCheck := IsLatin
    } else {
        ; Русского больше: чиним только английские токены в RU.
        table := GetConversionTable("EN_TO_RU")
        minorityCheck := IsLatin
        majorityCheck := IsCyrillic
    }

    out := ""
    token := ""
    changed := false

    for ch in StrSplit(text) {
        if IsWhitespaceChar(ch) {
            if (token != "") {
                converted := ConvertTokenIfMinority(token, table, minorityCheck, majorityCheck, &didChange)
                out .= converted
                changed := changed || didChange
                token := ""
            }

            out .= ch
        } else {
            token .= ch
        }
    }

    if (token != "") {
        converted := ConvertTokenIfMinority(token, table, minorityCheck, majorityCheck, &didChange)
        out .= converted
        changed := changed || didChange
    }

    return changed ? out : text
}


ConvertTokenIfMinority(token, table, minorityCheck, majorityCheck, &didChange) {
    if IsExcludedToken(token) {
        didChange := false
        return token
    }

    hasMinority := false
    hasMajority := false

    for ch in StrSplit(token) {
        if minorityCheck(ch) {
            hasMinority := true
        }

        if majorityCheck(ch) {
            hasMajority := true
        }
    }

    ; Конвертируем только чистые токены меньшинства.
    ; Если в одном токене смешаны RU и EN — не трогаем.
    if !(hasMinority && !hasMajority) {
        didChange := false
        return token
    }

    out := ""

    for ch in StrSplit(token) {
        out .= table.Has(ch) ? table[ch] : ch
    }

    didChange := true
    return out
}


; ============================================================
; Live: двойной пробел или альтернативный хоткей
; ============================================================

HandleLiveContextBreak(*) {
    global g_LiveBusy, g_LivePendingBuffer
    global g_LiveContextInvalidated, g_LiveOperationWindow

    if g_LiveBusy {
        g_LivePendingBuffer := ""
        g_LiveContextInvalidated := true
        g_LiveOperationWindow := WinExist("A")
    }

    ResetTypingBuffer()
}


SyncLivePendingContext() {
    global g_LivePendingBuffer
    global g_LiveContextInvalidated, g_LiveOperationWindow

    currentWindow := WinExist("A")

    if (g_LiveOperationWindow && currentWindow != g_LiveOperationWindow) {
        g_LivePendingBuffer := ""
        g_LiveContextInvalidated := true
        g_LiveOperationWindow := currentWindow
    }
}


AppendLivePendingChar(char) {
    global g_LivePendingBuffer
    global g_MaxBufferChars

    SyncLivePendingContext()
    g_LivePendingBuffer .= char

    if (StrLen(g_LivePendingBuffer) > g_MaxBufferChars) {
        g_LivePendingBuffer := SubStr(g_LivePendingBuffer, StrLen(g_LivePendingBuffer) - g_MaxBufferChars + 1)
    }
}


HandleLiveSpaceWhileBusy() {
    global g_LivePendingBuffer, g_MaxBufferChars

    ; Пока идёт замена, любой новый пробел остаётся обычным вводом.
    ; Повторную live-команду здесь не ставим в очередь: она неотличима
    ; от быстрой печати и раньше могла снова проглотить пробел.
    SyncLivePendingContext()
    g_LivePendingBuffer .= " "

    if (StrLen(g_LivePendingBuffer) > g_MaxBufferChars) {
        g_LivePendingBuffer := SubStr(g_LivePendingBuffer, StrLen(g_LivePendingBuffer) - g_MaxBufferChars + 1)
    }

    SendPlainSpace()
}


FlushLivePendingAfterOperation(replacementApplied := true, contextInvalidated := false) {
    global g_LivePendingBuffer
    global g_Buffer

    pendingBuffer := g_LivePendingBuffer

    g_LivePendingBuffer := ""

    ; После перемещения курсора или смены контекста старый фрагмент больше
    ; нельзя связывать с текущей позицией. Оставляем только новый ввод.
    if contextInvalidated {
        g_Buffer := pendingBuffer
        RecalculateBufferState()
        return
    }

    if (pendingBuffer = "") {
        return
    }

    if replacementApplied {
        ; Старый фрагмент заменён: pending стал новым текущим фрагментом.
        g_Buffer := pendingBuffer
    } else {
        ; Замена не началась: pending уже находится после исходного текста.
        g_Buffer .= pendingBuffer
    }

    RecalculateBufferState()
}


LiveConvertHotkeyPressed(*) {
    global g_LiveEnabled, g_LiveTriggerMode, g_LiveBusy
    global g_Buffer, g_LivePendingBuffer
    global g_LiveContextInvalidated, g_LiveOperationWindow
    global g_LastSpaceTick, g_LastWindow

    operationStarted := false
    rawFragment := ""
    targetWindow := 0

    Critical "On"

    try {
        ; Повторный хоткей во время уже идущей замены полностью игнорируется.
        ; Обычный физический ввод при этом продолжает собираться в pending.
        if (g_LiveEnabled && g_LiveTriggerMode = "Hotkey" && !g_LiveBusy) {
            currentWindow := WinExist("A")

            if (currentWindow != g_LastWindow) {
                g_LastWindow := currentWindow
                ResetTypingBuffer()
            }

            g_LastSpaceTick := 0
            rawFragment := g_Buffer
            targetWindow := currentWindow
            g_LivePendingBuffer := ""
            g_LiveContextInvalidated := false
            g_LiveOperationWindow := targetWindow
            g_LiveBusy := true
            operationStarted := true
        }
    } finally {
        Critical "Off"
    }

    if !operationStarted {
        return
    }

    return TryLiveConvertHotkey(rawFragment, targetWindow)
}


LiveSpacePressed() {
    global g_LiveEnabled, g_LiveTriggerMode, g_LiveBusy
    global g_Buffer, g_LivePendingBuffer
    global g_LiveContextInvalidated, g_LiveOperationWindow
    global g_LastSpaceTick, g_DoubleSpaceMs
    global g_LastWindow

    ; Распознавание второго пробела, снимок фрагмента и переход в busy —
    ; одна транзакция. Быстрый следующий символ уже попадёт только в pending.
    Critical "On"

    try {
        shiftDown := GetKeyState("Shift", "P")

        ; Ctrl/Alt/Win+Space — команда приложения, а не live-триггер.
        ; Проверяем это до busy-ветки, чтобы сочетание не попало в pending-буфер.
        if (GetKeyState("Ctrl", "P")
         || GetKeyState("Alt", "P")
         || GetKeyState("LWin", "P")
         || GetKeyState("RWin", "P")) {
            g_LastSpaceTick := 0

            if g_LiveBusy {
                g_LivePendingBuffer := ""
                g_LiveContextInvalidated := true
            } else {
                ResetTypingBuffer()
            }

            Send "{Blind}{Space}"
            return
        }

        ; Если live уже выполняет замену, не запускаем вторую операцию параллельно.
        ; Вместо этого собираем новый ввод в pending-буфер.
        if g_LiveBusy {
            HandleLiveSpaceWhileBusy()
            return
        }

        ; Защитная ветка на случай переключения режима между событием и callback.
        if (!g_LiveEnabled || g_LiveTriggerMode != "DoubleSpace") {
            SendPlainSpace()
            return
        }

        currentWindow := WinExist("A")
        if (currentWindow != g_LastWindow) {
            g_LastWindow := currentWindow
            ResetTypingBuffer()
        }

        ; Shift+Space остаётся обычным пробелом, но никогда не является
        ; второй половиной live-команды.
        if shiftDown {
            AppendLiveSpaceToBuffer(false)
            SendPlainSpace()
            return
        }

        elapsed := A_TickCount - g_LastSpaceTick

        if !(g_LastSpaceTick != 0
         && EndsWithSpace(g_Buffer)
         && elapsed >= 0
         && elapsed <= g_DoubleSpaceMs) {
            ; Первый обычный пробел: отправляем в приложение и добавляем в буфер.
            AppendLiveSpaceToBuffer()
            SendPlainSpace()
            return
        }

        ; Второй пробел сразу отправляем в приложение и фиксируем точную границу
        ; команды. Всё последующее физическое нажатие пойдёт в pending-буфер.
        g_LastSpaceTick := 0
        AppendLiveSpaceToBuffer(false)

        rawFragment := g_Buffer
        targetWindow := currentWindow
        g_LivePendingBuffer := ""
        g_LiveContextInvalidated := false
        g_LiveOperationWindow := targetWindow
        g_LiveBusy := true
        SendPlainSpace()
    } finally {
        Critical "Off"
    }

    return TryLiveConvertDoubleSpace(rawFragment, targetWindow)
}


AppendLiveSpaceToBuffer(armDoubleSpace := true) {
    global g_Buffer, g_LastSpaceTick, g_MaxBufferChars

    g_Buffer .= " "

    if (StrLen(g_Buffer) > g_MaxBufferChars) {
        g_Buffer := SubStr(g_Buffer, StrLen(g_Buffer) - g_MaxBufferChars + 1)
        ClearLiveBoundaryPrefix()
    }

    RecalculateBufferState()

    g_LastSpaceTick := armDoubleSpace ? A_TickCount : 0
}


SendPlainSpace() {
    Send "{Blind}{Space}"
}


IH_OnChar(ih, char) {
    global g_LiveEnabled, g_LiveTriggerMode, g_LiveBusy
    global g_Buffer
    global g_LastSpaceTick, g_MaxBufferChars
    global g_LastWindow
    global g_HotkeyCaptureActive

    if (!g_LiveEnabled || g_HotkeyCaptureActive) {
        return
    }

    ; В режиме двойного пробела Space ловит отдельный hotkey. В режиме по
    ; хоткею пробел проходит в приложение сам и здесь только попадает в буфер.
    if (char = " ") {
        if (g_LiveTriggerMode != "Hotkey") {
            return
        }

        if g_LiveBusy {
            AppendLivePendingChar(char)
            return
        }

        g_LastSpaceTick := 0

        currentWindow := WinExist("A")
        if (currentWindow != g_LastWindow) {
            g_LastWindow := currentWindow
            ResetTypingBuffer()
        }

        AppendLiveSpaceToBuffer(false)
        return
    }

    ; Если live сейчас занят заменой текста, физический ввод пользователя
    ; складываем во временный pending-буфер, а не теряем.
    if g_LiveBusy {
        AppendLivePendingChar(char)
        return
    }

    ; I1 уже отфильтровал искусственный ввод AHK. Значит этот символ
    ; физический и обязан сразу отменить ожидание второго пробела.
    g_LastSpaceTick := 0

    currentWindow := WinExist("A")
    if (currentWindow != g_LastWindow) {
        g_LastWindow := currentWindow
        ResetTypingBuffer()
    }

    g_Buffer .= char

    if (StrLen(g_Buffer) > g_MaxBufferChars) {
        g_Buffer := SubStr(g_Buffer, StrLen(g_Buffer) - g_MaxBufferChars + 1)
        ClearLiveBoundaryPrefix()
    }

    ; Пересчёт подтверждает границу только после пробела. Когда затем начинается
    ; новое предложение, старый текст отбрасывается, но сам знак с пробелами
    ; переносится в начало нового заменяемого фрагмента.
    RecalculateBufferState()
}

IsLiveSpaceArmBreakerKey(keyName) {
    return keyName != "Space"
}


IsLiveModifierKey(keyName) {
    static modifiers := Map(
        "Shift", true,
        "LShift", true,
        "RShift", true,
        "Ctrl", true,
        "Control", true,
        "LControl", true,
        "RControl", true,
        "Alt", true,
        "LAlt", true,
        "RAlt", true,
        "LWin", true,
        "RWin", true,
        "CapsLock", true,
        "NumLock", true,
        "ScrollLock", true
    )

    return modifiers.Has(keyName)
}


GetHotkeyMainKey(hotkeyName) {
    keyName := Trim(hotkeyName)
    keyName := RegExReplace(keyName, "^[~*$<>^!+#]+")
    keyName := Trim(StrReplace(StrReplace(keyName, "{", ""), "}", ""))
    return keyName
}


IsHotkeyChordActive(hotkeyName, keyName) {
    hotkeyName := Trim(hotkeyName)

    if (hotkeyName = "" || StrLower(GetHotkeyMainKey(hotkeyName)) != StrLower(keyName)) {
        return false
    }

    if InStr(hotkeyName, "*") {
        return true
    }

    ; Учитываем не только физическую клавиатуру, но и экранные клавиатуры
    ; и другие средства ввода, которые создают обычное логическое нажатие.
    ctrlDown := GetKeyState("Ctrl")
    altDown := GetKeyState("Alt")
    shiftDown := GetKeyState("Shift")
    winDown := GetKeyState("LWin") || GetKeyState("RWin")

    return ctrlDown = !!InStr(hotkeyName, "^")
        && altDown = !!InStr(hotkeyName, "!")
        && shiftDown = !!InStr(hotkeyName, "+")
        && winDown = !!InStr(hotkeyName, "#")
}


IH_OnKeyDown(ih, vk, sc) {
    global g_LiveEnabled, g_LiveTriggerMode, g_LiveBusy
    global g_Buffer, g_LastSpaceTick, g_LivePendingBuffer
    global g_LiveContextInvalidated
    global g_HotkeyLiveConvert, g_HotkeyCaptureActive

    if (!g_LiveEnabled || g_HotkeyCaptureActive) {
        return
    }

    keyName := GetKeyName(Format("vk{:02X}sc{:03X}", vk, sc))

    ; Основная клавиша Live-хоткея не должна очищать накопленный фрагмент.
    ; Во время busy это же условие позволяет полностью проигнорировать повтор.
    if (g_LiveTriggerMode = "Hotkey" && IsHotkeyChordActive(g_HotkeyLiveConvert, keyName)) {
        g_LastSpaceTick := 0
        return
    }

    ; Важно:
    ; $*Space ловит пробел отдельно.
    ; Но если между двумя пробелами была любая другая физическая клавиша,
    ; значит это НЕ двойной пробел для live-конвертации.
    ; Во время busy правим только pending-буфер, не старый основной.
    if g_LiveBusy {
        SyncLivePendingContext()

        switch keyName {
            case "Backspace":
                if (StrLen(g_LivePendingBuffer) > 0) {
                    g_LivePendingBuffer := SubStr(g_LivePendingBuffer, 1, StrLen(g_LivePendingBuffer) - 1)
                } else {
                    g_LiveContextInvalidated := true
                }

            case "Enter", "Tab", "Esc", "Escape", "Left", "Right", "Up", "Down", "Home", "End", "Delete", "PgUp", "PgDn":
                g_LivePendingBuffer := ""
                g_LiveContextInvalidated := true

            default:
                if !IsLiveModifierKey(keyName) {
                    g_LivePendingBuffer := ""
                    g_LiveContextInvalidated := true
                }
        }

        return
    }

    if IsLiveSpaceArmBreakerKey(keyName) {
        g_LastSpaceTick := 0
    }

    switch keyName {
        case "Backspace":
            if (StrLen(g_Buffer) > 0) {
                g_Buffer := SubStr(g_Buffer, 1, StrLen(g_Buffer) - 1)
                RecalculateBufferState()
            }

        case "Enter", "Tab", "Esc", "Escape", "Left", "Right", "Up", "Down", "Home", "End", "Delete", "PgUp", "PgDn":
            ResetTypingBuffer()

        default:
            if !IsLiveModifierKey(keyName) {
                ResetTypingBuffer()
            }
    }
}


TryLiveConvertDoubleSpace(rawFragment, targetWindow) {
    global g_AppName

    return DoLiveConvertAndReplace(rawFragment, g_AppName " — Live-режим", targetWindow, " ")
}


TryLiveConvertHotkey(rawFragment, targetWindow) {
    global g_AppName

    ; Хоткей ничего не добавляет, но уже введённые пользователем пробелы
    ; в конце фрагмента сохраняет.
    fragmentWithoutTrailingSpace := RTrim(rawFragment, " `t`r`n")
    existingTrailingSpace := SubStr(rawFragment, StrLen(fragmentWithoutTrailingSpace) + 1)

    return DoLiveConvertAndReplace(
        rawFragment,
        g_AppName " — Live-режим",
        targetWindow,
        existingTrailingSpace
    )
}


DoLiveConvertAndReplace(rawFragment, title, targetWindow, replacementSuffix := " ") {
    global g_LiveBusy, g_LivePendingBuffer
    global g_LiveContextInvalidated, g_LiveOperationWindow
    global g_LiveBoundarySourcePrefix, g_LiveBoundaryReplacementPrefix

    fragment := RTrim(rawFragment, " `t`r`n")

    if (fragment = "") {
        Notify("Нет текста для исправления", title, "Icon!")
        FinishLiveOperation(false, targetWindow)
        return false
    }

    boundaryPrefixLength := 0
    boundaryReplacement := ""

    if (g_LiveBoundarySourcePrefix != ""
     && SubStr(fragment, 1, StrLen(g_LiveBoundarySourcePrefix)) = g_LiveBoundarySourcePrefix) {
        boundaryPrefixLength := StrLen(g_LiveBoundarySourcePrefix)
        boundaryReplacement := g_LiveBoundaryReplacementPrefix
    }

    conversionBody := SubStr(fragment, boundaryPrefixLength + 1)
    direction := DetectDirectionFromText(conversionBody)

    if (direction = "") {
        Notify("Не удалось определить раскладку", title, "Icon!")
        FinishLiveOperation(false, targetWindow)
        return false
    }

    converted := boundaryReplacement . ConvertTextByDirection(conversionBody, direction)

    if (converted = fragment) {
        Notify("В текущем фрагменте нечего исправлять", title, "Iconi")
        FinishLiveOperation(false, targetWindow)
        return false
    }

    deleteCount := StrLen(rawFragment)

    if (deleteCount <= 0) {
        FinishLiveOperation(false, targetWindow)
        return false
    }

    clipboardSaved := false
    replacementStarted := false
    replacementCompleted := false

    try {
        oldClipboard := ClipboardAll()
        clipboardSaved := true

        A_Clipboard := ""
        A_Clipboard := converted . replacementSuffix

        if !ClipWait(0.5) {
            Notify("Не удалось подготовить исправленный текст. Буфер обмена восстановлен", title, "Icon!")
        } else if (g_LiveContextInvalidated || WinExist("A") != targetWindow) {
            Notify("Исправление отменено: изменилось место ввода", title, "Icon!")
        } else {
            finalContextChanged := false

            ; Не позволяем InputHook/click-callback вклиниться между последней
            ; проверкой контекста, снимком pending и единственным SendInput.
            ; Сам SendInput буферизует физический ввод до конца последовательности.
            Critical "On"

            try {
                if (g_LiveContextInvalidated || WinExist("A") != targetWindow) {
                    finalContextChanged := true
                } else {
                    ; Всё, что пользователь успел допечатать после второго пробела,
                    ; уже видно в приложении. Удаляем это вместе со старым фрагментом
                    ; и возвращаем в конце той же SendInput-последовательности.
                    pendingSnapshot := g_LivePendingBuffer
                    totalDeleteCount := deleteCount + StrLen(pendingSnapshot)
                    sendSequence := "{Backspace " . totalDeleteCount . "}^v"

                    if (pendingSnapshot != "") {
                        sendSequence .= "{Text}" pendingSnapshot
                    }

                    replacementStarted := true
                    Send sendSequence
                    replacementCompleted := true
                    ResetTypingBuffer(false)
                }
            } finally {
                Critical "Off"
            }

            if finalContextChanged {
                Notify("Исправление отменено: изменилось место ввода", title, "Icon!")
            } else if replacementCompleted {
                ; Даём приложению прочитать данные буфера до его восстановления.
                Sleep 450
                Notify("Исправлено: " SubStr(converted, 1, 60) (StrLen(converted) > 60 ? "..." : ""), title, "Iconi", true)
            }
        }
    } catch as err {
        if (replacementStarted && !replacementCompleted) {
            g_LiveContextInvalidated := true
            ResetTypingBuffer(false)
        }

        Notify("Ошибка конвертации: " err.Message, title, "Iconx")
    }

    if clipboardSaved {
        try {
            A_Clipboard := oldClipboard
        }
    }

    FinishLiveOperation(replacementCompleted, targetWindow)
    return replacementCompleted
}


FinishLiveOperation(replacementApplied, targetWindow) {
    global g_LiveBusy
    global g_LiveContextInvalidated, g_LiveOperationWindow
    global g_LastWindow

    ; Сливаем pending и только затем открываем обычную ветку InputHook.
    ; Иначе символ на границе мог попасть в g_Buffer, а Flush — затереть его.
    Critical "On"

    try {
        ; Окно могло смениться после последнего callback. Отбрасываем pending
        ; старого окна и привязываем итоговый буфер к реально активному.
        SyncLivePendingContext()
        currentWindow := WinExist("A")
        contextInvalidated := g_LiveContextInvalidated || currentWindow != targetWindow
        g_LastWindow := currentWindow
        FlushLivePendingAfterOperation(replacementApplied, contextInvalidated)
    } finally {
        g_LiveContextInvalidated := false
        g_LiveOperationWindow := 0
        g_LiveBusy := false
        Critical "Off"
    }
}


ResetTypingBuffer(resetWindow := true) {
    global g_Buffer, g_Direction
    global g_LastSpaceTick
    global g_PendingBoundary, g_AfterBoundarySpace, g_BoundaryStart
    global g_LiveBoundarySourcePrefix, g_LiveBoundaryReplacementPrefix
    global g_LastWindow

    g_Buffer := ""
    g_Direction := ""
    g_LastSpaceTick := 0
    g_PendingBoundary := false
    g_AfterBoundarySpace := false
    g_BoundaryStart := 0
    g_LiveBoundarySourcePrefix := ""
    g_LiveBoundaryReplacementPrefix := ""

    if (resetWindow) {
        g_LastWindow := WinExist("A")
    }
}


RecalculateBufferState() {
    global g_Buffer, g_Direction
    global g_PendingBoundary, g_AfterBoundarySpace, g_BoundaryStart
    global g_LiveBoundarySourcePrefix, g_LiveBoundaryReplacementPrefix

    prefixLength := StrLen(g_LiveBoundarySourcePrefix)

    if (prefixLength > 0
     && (StrLen(g_Buffer) < prefixLength
      || SubStr(g_Buffer, 1, prefixLength) != g_LiveBoundarySourcePrefix)) {
        ClearLiveBoundaryPrefix()
        prefixLength := 0
    }

    body := SubStr(g_Buffer, prefixLength + 1)
    g_Direction := ""
    g_PendingBoundary := false
    g_AfterBoundarySpace := false
    g_BoundaryStart := 0

    chars := StrSplit(body)

    Loop chars.Length {
        ch := chars[A_Index]

        if IsWhitespaceChar(ch) {
            if g_PendingBoundary {
                g_AfterBoundarySpace := true
            }
            continue
        }

        if (g_PendingBoundary && g_AfterBoundarySpace) {
            absoluteBoundaryStart := prefixLength + g_BoundaryStart
            sourcePrefix := SubStr(g_Buffer, absoluteBoundaryStart, prefixLength + A_Index - absoluteBoundaryStart)

            g_Buffer := sourcePrefix . SubStr(body, A_Index)
            g_LiveBoundarySourcePrefix := sourcePrefix
            g_LiveBoundaryReplacementPrefix := NormalizeLiveBoundaryPrefix(sourcePrefix)
            return RecalculateBufferState()
        }

        if (g_PendingBoundary && !g_AfterBoundarySpace) {
            ; Последовательности вроде "?!" считаем одной границей. Если же
            ; сразу продолжилось слово (например, пиво/водка), кандидат отменяем.
            if !IsBoundaryChar(ch, g_Direction) {
                g_PendingBoundary := false
                g_BoundaryStart := 0
            }
        }

        if (g_Direction = "") {
            d := DirectionFromChar(ch)
            if (d != "") {
                g_Direction := d
            }
        }

        if (g_Direction != "" && IsBoundaryChar(ch, g_Direction)) {
            if !g_PendingBoundary {
                g_BoundaryStart := A_Index
            }
            g_PendingBoundary := true
            g_AfterBoundarySpace := false
        }
    }
}


ClearLiveBoundaryPrefix() {
    global g_LiveBoundarySourcePrefix, g_LiveBoundaryReplacementPrefix

    g_LiveBoundarySourcePrefix := ""
    g_LiveBoundaryReplacementPrefix := ""
}


NormalizeLiveBoundaryPrefix(prefix) {
    out := ""

    for ch in StrSplit(prefix) {
        switch ch {
            case "/", "ю", "Ю":
                out .= "."
            case "&", ",":
                out .= "?"
            default:
                out .= ch
        }
    }

    return out
}


DetectDirectionFromText(text) {
    for ch in StrSplit(text) {
        d := DirectionFromChar(ch)
        if (d != "") {
            return d
        }
    }

    return ""
}


DirectionFromChar(ch) {
    if (IsLatin(ch)) {
        return "EN_TO_RU"
    }

    if (IsCyrillic(ch)) {
        return "RU_TO_EN"
    }

    return ""
}


IsBoundaryChar(ch, direction) {
    ; Обычная пунктуация тоже завершает предложение. Раньше Live видел
    ; только символы, искажённые неверной раскладкой, поэтому мог захватить
    ; текст из предыдущего предложения.
    if (ch = "." || ch = "?" || ch = "!" || ch = "…") {
        return true
    }

    if (direction = "EN_TO_RU") {
        ; Когда русский текст ошибочно набран в EN-раскладке:
        ; / → .
        ; & → ?
        ; ! → !
        return ch = "/" || ch = "&"
    }

    if (direction = "RU_TO_EN") {
        ; Когда английский текст ошибочно набран в RU-раскладке:
        ; ю → .
        ; , → ?
        ; ! → !
        return ch = "ю" || ch = "Ю" || ch = ","
    }

    return false
}


IsWhitespaceChar(ch) {
    return ch = " " || ch = "`t" || ch = "`n" || ch = "`r"
}


EndsWithSpace(text) {
    return StrLen(text) > 0 && SubStr(text, StrLen(text), 1) = " "
}


IsLatin(ch) {
    code := Ord(ch)
    return ((code >= 65 && code <= 90) || (code >= 97 && code <= 122))
}


IsCyrillic(ch) {
    code := Ord(ch)
    return ((code >= 1040 && code <= 1103) || code = 1025 || code = 1105)
}


ConvertTextByDirection(text, direction) {
    table := GetConversionTable(direction)
    out := ""

    for part in SplitByWhitespace(text) {
        if IsExcludedToken(part) {
            out .= part
            continue
        }

        for ch in StrSplit(part) {
            out .= table.Has(ch) ? table[ch] : ch
        }
    }

    return out
}


GetConversionTable(direction) {
    static enToRu := Map(
        Chr(96), "ё", "~", "Ё",

        "q", "й", "w", "ц", "e", "у", "r", "к", "t", "е", "y", "н", "u", "г", "i", "ш", "o", "щ", "p", "з",
        "[", "х", "]", "ъ",
        "a", "ф", "s", "ы", "d", "в", "f", "а", "g", "п", "h", "р", "j", "о", "k", "л", "l", "д",
        ";", "ж", "'", "э",
        "z", "я", "x", "ч", "c", "с", "v", "м", "b", "и", "n", "т", "m", "ь",
        ",", "б", ".", "ю", "/", ".",
        "?", ",",

        "Q", "Й", "W", "Ц", "E", "У", "R", "К", "T", "Е", "Y", "Н", "U", "Г", "I", "Ш", "O", "Щ", "P", "З",
        "{", "Х", "}", "Ъ",
        "A", "Ф", "S", "Ы", "D", "В", "F", "А", "G", "П", "H", "Р", "J", "О", "K", "Л", "L", "Д",
        ":", "Ж", Chr(34), "Э",
        "Z", "Я", "X", "Ч", "C", "С", "V", "М", "B", "И", "N", "Т", "M", "Ь",
        "<", "Б", ">", "Ю",

        "@", Chr(34),
        "#", "№",
        "$", ";",
        "^", ":",
        "&", "?"
    )

    static ruToEn := Map()

    if (ruToEn.Count = 0) {
        for en, ru in enToRu {
            ruToEn[ru] := en
        }
    }

    return direction = "EN_TO_RU" ? enToRu : ruToEn
}
