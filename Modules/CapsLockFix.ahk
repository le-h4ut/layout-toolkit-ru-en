; CapsLockFix.ahk
; Исправление регистра выделенного текста в умном и полном режимах.
;
; Зависит от функций основного LT:
; - SplitByWhitespace(text)
; - IsExcludedToken(token)
; - GetCanonicalExcludedToken(token)
; - Notify(message, title, options, forceSound := false)
;
; Примеры:
;   пРИВЕТ -> Привет
;   эТО пРИМЕР -> Это пример
;   тАК. пРИМЕР -> Так. Пример
;   мАМА ПОШЛА В МАГАЗИН -> Мама пошла в магазин (полный режим)
;   GitHUB -> GitHub
;   POWERSHELL -> PowerShell


CapsLockFixSelectedHotkey() {
    CapsFix_ReplaceSelectedText("Smart")
}


CapsLockFullFixSelectedHotkey() {
    CapsFix_ReplaceSelectedText("Full")
}


CapsFix_ReplaceSelectedText(mode) {
    global g_AppName

    isFullMode := mode = "Full"
    title := g_AppName (isFullMode ? " — CapsLock Full Fix" : " — CapsLock Fix")
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

    result := isFullMode ? FixCapsLockFullText(text) : FixCapsLockText(text)

    ; Изменение только регистра тоже требует вставки результата.
    if (result == text) {
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

        Notify("Регистр исправлен", title, "Iconi", true)
    } catch as err {
        try {
            A_Clipboard := oldClipboard
        }

        Notify("Не удалось вставить исправленный текст: " err.Message, title, "Iconx")
    }
}


FixCapsLockText(text) {
    out := ""
    capitalizeNext := true

    for part in SplitByWhitespace(text) {
        ; Сохраняем пробелы / переносы как есть.
        if part ~= "^\s+$" {
            out .= part

            ; После переноса строки следующее слово считаем началом новой фразы.
            if InStr(part, "`n") || InStr(part, "`r") {
                capitalizeNext := true
            }

            continue
        }

        ; exclude.txt работает как словарь канонического написания:
        ; GitHUB -> GitHub
        ; POWERSHELL -> PowerShell
        if IsExcludedToken(part) {
            canonical := GetCanonicalExcludedToken(part)

            if (canonical != "") {
                out .= canonical
            } else {
                out .= part
            }

            if CapsFix_TokenEndsSentence(part) {
                capitalizeNext := true
            } else {
                capitalizeNext := false
            }

            continue
        }

        fixed := CapsFix_SmartFixToken(part, capitalizeNext)
        out .= fixed

        if CapsFix_TokenEndsSentence(fixed) {
            capitalizeNext := true
        } else {
            capitalizeNext := false
        }
    }

    return out
}


CapsFix_SmartFixToken(token, capitalizeFirst := false) {
    trimChars := " `t`r`n'()[]{}<>.,;:!?" . Chr(34)

    core := Trim(token, trimChars)

    if (core = "") {
        return token
    }

    startPos := InStr(token, core)

    if (startPos <= 0) {
        return token
    }

    prefix := SubStr(token, 1, startPos - 1)
    suffix := SubStr(token, startPos + StrLen(core))

    if !CapsFix_ShouldFixCore(core) {
        return token
    }

    fixedCore := CapsFix_ToSentenceCore(core, capitalizeFirst)

    return prefix fixedCore suffix
}


CapsFix_ShouldFixCore(core) {
    upperCount := 0
    lowerCount := 0
    firstLetterSeen := false
    firstLetterIsLower := false

    Loop Parse core {
        ch := A_LoopField

        if CapsFix_IsUpperLetter(ch) {
            upperCount++

            if !firstLetterSeen {
                firstLetterSeen := true
            }
        } else if CapsFix_IsLowerLetter(ch) {
            lowerCount++

            if !firstLetterSeen {
                firstLetterSeen := true
                firstLetterIsLower := true
            }
        }
    }

    ; Вообще нет букв верхнего регистра — нечего чинить.
    if (upperCount = 0) {
        return false
    }

    ; Полный капс:
    ; YABAI / TEST / ПРИВЕТ / ПРИМЕР
    if (upperCount > 0 && lowerCount = 0) {
        return true
    }

    ; Классический случай случайного CapsLock:
    ; yABAI / пРИВЕТ / эТО
    if (firstLetterIsLower && upperCount > 0) {
        return true
    }

    ; Подозрительная пачка верхнего регистра внутри слова:
    ; GitHUB / abCD / helloWORLD
    if (upperCount >= 2) {
        return true
    }

    return false
}


CapsFix_ToSentenceCore(core, capitalizeFirst := false) {
    lower := CapsFix_ToLowerText(core)

    if !capitalizeFirst {
        return lower
    }

    return CapsFix_UpperFirstLetter(lower)
}


CapsFix_ToLowerText(text) {
    result := ""

    Loop Parse text {
        result .= CapsFix_ToLowerChar(A_LoopField)
    }

    return result
}


CapsFix_UpperFirstLetter(text) {
    result := ""
    firstLetterDone := false

    Loop Parse text {
        ch := A_LoopField

        if !firstLetterDone && CapsFix_IsAnyLetter(ch) {
            result .= CapsFix_ToUpperChar(ch)
            firstLetterDone := true
        } else {
            result .= ch
        }
    }

    return result
}


CapsFix_ToLowerChar(ch) {
    code := Ord(ch)

    ; A-Z -> a-z
    if (code >= 0x41 && code <= 0x5A) {
        return Chr(code + 32)
    }

    ; А-Я -> а-я
    if (code >= 0x410 && code <= 0x42F) {
        return Chr(code + 32)
    }

    ; Ё -> ё
    if (code = 0x401) {
        return Chr(0x451)
    }

    return ch
}


CapsFix_ToUpperChar(ch) {
    code := Ord(ch)

    ; a-z -> A-Z
    if (code >= 0x61 && code <= 0x7A) {
        return Chr(code - 32)
    }

    ; а-я -> А-Я
    if (code >= 0x430 && code <= 0x44F) {
        return Chr(code - 32)
    }

    ; ё -> Ё
    if (code = 0x451) {
        return Chr(0x401)
    }

    return ch
}


CapsFix_TokenEndsSentence(token) {
    trimmed := Trim(token)

    if (trimmed = "") {
        return false
    }

    lastChar := SubStr(trimmed, -1)

    return lastChar = "." || lastChar = "!" || lastChar = "?" || lastChar = "…" || lastChar = ":"
}


CapsFix_IsAnyLetter(ch) {
    return CapsFix_IsUpperLetter(ch) || CapsFix_IsLowerLetter(ch)
}


CapsFix_IsUpperLetter(ch) {
    code := Ord(ch)

    return (code >= 0x41 && code <= 0x5A)      ; A-Z
        || (code >= 0x410 && code <= 0x42F)    ; А-Я
        || (code = 0x401)                      ; Ё
}


CapsFix_IsLowerLetter(ch) {
    code := Ord(ch)

    return (code >= 0x61 && code <= 0x7A)      ; a-z
        || (code >= 0x430 && code <= 0x44F)    ; а-я
        || (code = 0x451)                      ; ё
}


FixCapsLockFullText(text) {
    out := ""

    for part in SplitByWhitespace(text) {
        if part ~= "^\s+$" {
            out .= part
            continue
        }

        ; Словарь исключений имеет приоритет над инверсией регистра и
        ; восстанавливает точное написание, например GitHub или PowerShell.
        if IsExcludedToken(part) {
            canonical := GetCanonicalExcludedToken(part)
            out .= canonical != "" ? canonical : part
            continue
        }

        out .= CapsFix_InvertText(part)
    }

    return out
}


CapsFix_InvertText(text) {
    result := ""

    Loop Parse text {
        ch := A_LoopField

        if CapsFix_IsUpperLetter(ch) {
            result .= CapsFix_ToLowerChar(ch)
        } else if CapsFix_IsLowerLetter(ch) {
            result .= CapsFix_ToUpperChar(ch)
        } else {
            result .= ch
        }
    }

    return result
}
